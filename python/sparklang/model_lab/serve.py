"""Tiny CPU serve forward from SPARK_BC / Spark safetensors.

Loads Spark-created weights (or emits init), runs embed→optional
layer-0 attn→optional MLP→norm→lm_head on CPU, writes SERVE with
forward=true and honest trained. Not a production LLM. Never the
voice GPU / 6000.
"""

from __future__ import annotations

import hashlib
import json
import math
import struct
from pathlib import Path
from typing import Any

from sparklang.model_lab.bc_dump import load_sparkbc
from sparklang.model_lab.weights import (
    emit_init_weights,
    read_safetensors,
)


def _unpack_f32(blob: bytes) -> list[float]:
    n = len(blob) // 4
    return list(struct.unpack("<%df" % n, blob))


def _row(mat: list[float], cols: int, row: int) -> list[float]:
    base = row * cols
    return mat[base : base + cols]


def _matmul_vec(
    weight: list[float],
    rows: int,
    cols: int,
    x: list[float],
) -> list[float]:
    """y = W @ x for W shaped (rows, cols), x length cols."""
    if len(x) != cols:
        raise ValueError("matmul width mismatch")
    out: list[float] = []
    for r in range(rows):
        base = r * cols
        s = 0.0
        for c in range(cols):
            s += weight[base + c] * x[c]
        out.append(s)
    return out


def _rms_norm(x: list[float], w: list[float], eps: float = 1e-5) -> list[float]:
    """Elementwise RMSNorm: x * w / rms(x)."""
    if len(x) != len(w):
        raise ValueError("norm size mismatch")
    mean_sq = sum(v * v for v in x) / float(len(x))
    inv = 1.0 / math.sqrt(mean_sq + eps)
    return [x[i] * inv * w[i] for i in range(len(x))]


def _token_ids_from_bc(raw: bytes, n: int, vocab: int) -> list[int]:
    """Deterministic prompt tokens from SPARK_BC bytes."""
    if n < 1:
        return [0]
    return [int(b) % vocab for b in raw[:n]]


def _silu(x: list[float]) -> list[float]:
    """SiLU / swish activation."""
    out: list[float] = []
    for v in x:
        out.append(v / (1.0 + math.exp(-v)))
    return out


def _mlp_block(
    hidden: list[float],
    tensors: dict[str, tuple[tuple[int, ...], bytes]],
    layer: int = 0,
) -> tuple[list[float], bool]:
    """Optional layer-N SwiGLU MLP residual if tensors exist."""
    p = "spark.layers.%d" % layer
    need = (
        p + ".mlp_norm.weight",
        p + ".mlp_up.weight",
        p + ".mlp_gate.weight",
        p + ".mlp_down.weight",
    )
    if any(k not in tensors for k in need):
        return hidden, False
    dim = len(hidden)
    norm_w = _unpack_f32(tensors[need[0]][1])
    up_shape, up_raw = tensors[need[1]]
    gate_shape, gate_raw = tensors[need[2]]
    down_shape, down_raw = tensors[need[3]]
    mlp = int(up_shape[0])
    if up_shape != (mlp, dim) or gate_shape != (mlp, dim):
        raise ValueError("mlp up/gate shape mismatch")
    if down_shape != (dim, mlp):
        raise ValueError("mlp down shape mismatch")
    x = _rms_norm(hidden, norm_w)
    up = _matmul_vec(_unpack_f32(up_raw), mlp, dim, x)
    gate = _matmul_vec(_unpack_f32(gate_raw), mlp, dim, x)
    act = _silu(gate)
    mid = [up[i] * act[i] for i in range(mlp)]
    down = _matmul_vec(_unpack_f32(down_raw), dim, mlp, mid)
    return [hidden[i] + down[i] for i in range(dim)], True


def _attn_block(
    hidden_seq: list[list[float]],
    tensors: dict[str, tuple[tuple[int, ...], bytes]],
    layer: int = 0,
) -> tuple[list[float], bool, dict[str, Any]]:
    """Optional layer-N last-query causal MHA; returns last hidden."""
    from sparklang.model_lab import attn as attn_mod

    p = "spark.layers.%d" % layer
    need = (
        p + ".attn_norm.weight",
        p + ".q.weight",
        p + ".k.weight",
        p + ".v.weight",
        p + ".o.weight",
    )
    if any(k not in tensors for k in need):
        dim = len(hidden_seq[0])
        acc = [0.0] * dim
        for row in hidden_seq:
            for i in range(dim):
                acc[i] += row[i]
        scale = 1.0 / float(len(hidden_seq))
        return [v * scale for v in acc], False, {}
    dim = len(hidden_seq[0])
    k_shape = tensors[need[2]][0]
    n_head = 4 if dim % 4 == 0 else 1
    hd = dim // n_head
    n_kv = max(1, int(k_shape[0]) // hd)
    y, _cache = attn_mod.attn_last_forward(
        hidden_seq,
        _unpack_f32(tensors[need[0]][1]),
        _unpack_f32(tensors[need[1]][1]),
        _unpack_f32(tensors[need[2]][1]),
        _unpack_f32(tensors[need[3]][1]),
        _unpack_f32(tensors[need[4]][1]),
        dim=dim,
        n_head=n_head,
        n_kv=n_kv,
    )
    return y, True, {"n_head": n_head, "n_kv": n_kv}


def _hidden_from_tokens(
    tensors: dict[str, tuple[tuple[int, ...], bytes]],
    token_ids: list[int],
) -> dict[str, Any]:
    """Embed → optional attn0 → optional mlp0 → final_norm."""
    embed_shape, embed_raw = tensors["spark.embed.weight"]
    norm_shape, norm_raw = tensors["spark.final_norm.weight"]
    vocab, dim = int(embed_shape[0]), int(embed_shape[1])
    if norm_shape != (dim,):
        raise ValueError("final_norm shape mismatch")
    embed = _unpack_f32(embed_raw)
    norm_w = _unpack_f32(norm_raw)
    ids = [int(t) % vocab for t in token_ids] or [0]
    seq: list[list[float]] = []
    for tid in ids:
        seq.append(_row(embed, dim, tid))
    hidden, used_attn, attn_meta = _attn_block(seq, tensors, 0)
    hidden, used_mlp = _mlp_block(hidden, tensors, 0)
    hidden = _rms_norm(hidden, norm_w)
    parts = ["embed"]
    if used_attn:
        parts.append("attn0")
    else:
        parts.append("mean_pool")
    if used_mlp:
        parts.append("mlp0")
    parts.append("rms_norm")
    out = {
        "token_ids": ids,
        "hidden": hidden,
        "hidden_dim": dim,
        "vocab": vocab,
        "attn0": used_attn,
        "mlp0": used_mlp,
        "path": "->".join(parts),
    }
    out.update(attn_meta)
    return out


def run_tiny_embed(
    tensors: dict[str, tuple[tuple[int, ...], bytes]],
    token_ids: list[int],
) -> dict[str, Any]:
    """CPU embedding vector (post-norm hidden). Not production."""
    h = _hidden_from_tokens(tensors, token_ids)
    return {
        "token_ids": h["token_ids"],
        "hidden_dim": h["hidden_dim"],
        "vocab": h["vocab"],
        "embedding": [round(v, 6) for v in h["hidden"]],
        "attn0": h.get("attn0", False),
        "mlp0": h["mlp0"],
        "path": h["path"],
    }


def run_tiny_forward(
    tensors: dict[str, tuple[tuple[int, ...], bytes]],
    token_ids: list[int],
) -> dict[str, Any]:
    """CPU embed → optional attn0 → optional MLP0 → norm → lm_head.

    Real matmuls + logits, not a marker-only stub. Not production.
    """
    head_shape, head_raw = tensors["spark.lm_head.weight"]
    h = _hidden_from_tokens(tensors, token_ids)
    vocab, dim = int(h["vocab"]), int(h["hidden_dim"])
    if head_shape != (vocab, dim):
        raise ValueError("lm_head shape mismatch")
    head = _unpack_f32(head_raw)
    logits = _matmul_vec(head, vocab, dim, h["hidden"])
    argmax = max(range(vocab), key=lambda i: logits[i])
    preview_n = min(8, vocab)
    path = h["path"] + "->lm_head"
    return {
        "token_ids": h["token_ids"],
        "hidden_dim": dim,
        "vocab": vocab,
        "logits_preview": [
            round(logits[i], 6) for i in range(preview_n)
        ],
        "argmax": argmax,
        "logit_max": round(logits[argmax], 6),
        "attn0": h.get("attn0", False),
        "mlp0": h["mlp0"],
        "path": path,
    }


def _honest_trained(meta: dict[str, str]) -> bool:
    """trained is true only when weights meta says so."""
    return str(meta.get("trained", "false")).lower() in (
        "true",
        "1",
        "yes",
    )


def emit_serve_stub(
    sparkbc_path: str | Path,
    dest_dir: str | Path,
    *,
    source: str = "",
    command: str = "",
    job_id: str = "serve-dry-001",
    weights_path: str | Path | None = None,
) -> dict[str, Any]:
    """Load/init weights, run tiny CPU forward, write SERVE artifact.

    Compatibility name: historically a dry marker. Now runs a real
    forward and sets forward=true. Still not production inference.
    """
    bc = load_sparkbc(sparkbc_path)
    out = Path(dest_dir)
    out.mkdir(parents=True, exist_ok=True)
    wpath = Path(weights_path) if weights_path else out / "weights.safetensors"
    if not wpath.is_file():
        emit_init_weights(
            sparkbc_path,
            wpath,
            source=source or str(sparkbc_path),
            command=command or "(already compiled)",
        )
    meta, tensors = read_safetensors(wpath)
    vocab = int(tensors["spark.embed.weight"][0][0])
    token_ids = _token_ids_from_bc(bc["raw"], 8, vocab)
    fwd = run_tiny_forward(tensors, token_ids)
    trained = _honest_trained(meta)
    marker = out / "SERVE"
    w_sha = hashlib.sha256(wpath.read_bytes()).hexdigest()
    payload: dict[str, Any] = {
        "op": "serve",
        "mode": "cpu-forward",
        "status": "implemented",
        "job_id": job_id,
        "genome": "SPARK_BC",
        "sparkbc": str(sparkbc_path),
        "sha256": bc["sha256"],
        "size_bytes": bc["size"],
        "source": source or str(sparkbc_path),
        "command": command or "(already compiled)",
        "weights": str(wpath),
        "weights_sha256": w_sha,
        "served": True,
        "forward": True,
        "trained": trained,
        "not_sgd": str(meta.get("not_sgd", "true")).lower()
        not in ("false", "0", "no"),
        "production": False,
        "forward_result": fwd,
        "note": (
            "tiny CPU forward (embed→optional attn0→optional "
            "mlp0→norm→lm_head); not a production LLM; "
            "trained follows weights meta"
        ),
        "marker": str(marker),
    }
    marker.write_text(
        json.dumps(payload, indent=2) + "\n",
        encoding="utf-8",
    )
    return payload


# Prefer this name in new call sites; stub remains for imports.
emit_serve_forward = emit_serve_stub
