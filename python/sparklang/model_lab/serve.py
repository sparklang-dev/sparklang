"""Tiny CPU serve forward from SPARK_BC / Spark safetensors.

Loads Spark-created weights (or emits init), runs one embed→norm→lm_head
matmul for logits, writes SERVE with forward=true and honest trained.
Not a production LLM. CPU only — never the voice GPU.
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


def run_tiny_forward(
    tensors: dict[str, tuple[tuple[int, ...], bytes]],
    token_ids: list[int],
) -> dict[str, Any]:
    """One CPU embed → final_norm → lm_head logit path.

    Skips full attention/MLP — still a real matmul + logits, not a
    marker-only stub. Not a production LLM.
    """
    embed_shape, embed_raw = tensors["spark.embed.weight"]
    head_shape, head_raw = tensors["spark.lm_head.weight"]
    norm_shape, norm_raw = tensors["spark.final_norm.weight"]
    vocab, dim = int(embed_shape[0]), int(embed_shape[1])
    if head_shape != (vocab, dim):
        raise ValueError("lm_head shape mismatch")
    if norm_shape != (dim,):
        raise ValueError("final_norm shape mismatch")
    embed = _unpack_f32(embed_raw)
    head = _unpack_f32(head_raw)
    norm_w = _unpack_f32(norm_raw)

    ids = [int(t) % vocab for t in token_ids] or [0]
    # Mean-pool token embeddings (tiny control path).
    acc = [0.0] * dim
    for tid in ids:
        row = _row(embed, dim, tid)
        for i in range(dim):
            acc[i] += row[i]
    scale = 1.0 / float(len(ids))
    hidden = [v * scale for v in acc]
    hidden = _rms_norm(hidden, norm_w)
    logits = _matmul_vec(head, vocab, dim, hidden)
    argmax = max(range(vocab), key=lambda i: logits[i])
    preview_n = min(8, vocab)
    return {
        "token_ids": ids,
        "hidden_dim": dim,
        "vocab": vocab,
        "logits_preview": [round(logits[i], 6) for i in range(preview_n)],
        "argmax": argmax,
        "logit_max": round(logits[argmax], 6),
        "path": "embed_mean_pool->rms_norm->lm_head",
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
            "tiny CPU forward (embed→norm→lm_head); "
            "not a production LLM; trained follows weights meta"
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
