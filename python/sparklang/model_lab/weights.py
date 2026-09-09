"""Emit Spark-created init weights from SPARK_BC. Not trained.

Better than a two-tensor hash stub: a named control-model layout
whose sizes and values come from the full bytecode (header, strings,
opcodes), plus fan-in scaled init. No imported checkpoints.
"""

from __future__ import annotations

import hashlib
import json
import math
import struct
from pathlib import Path
from typing import Any

from sparklang.model_lab.bc_dump import (
    decode_ops,
    hex_preview,
    load_sparkbc,
)

# Tiny control decoder — Spark-created base, not a 3B claim.
VOCAB = 256
DIM = 32
N_LAYER = 2
N_HEAD = 4
N_KV = 2
HEAD_DIM = DIM // N_HEAD
MLP = DIM * 4


def arch_from_bc(bc: dict[str, Any]) -> dict[str, int]:
    """Sizes from SPARK_BC, clamped so the stub stays small."""
    ncode = max(1, int(bc["ncode"]))
    nstr = max(1, len(bc["strings"]))
    dim = 16
    while dim < 32 and dim < 8 * nstr:
        dim *= 2
    layers = 2 if ncode >= 8 else 1
    return {
        "vocab": VOCAB,
        "dim": dim,
        "n_layer": layers,
        "n_head": N_HEAD,
        "n_kv": N_KV,
        "head_dim": dim // N_HEAD,
        "mlp": dim * 4,
    }


def _stream(seed: bytes, count: int) -> list[float]:
    """Unit stream in (-1, 1) from SHA-256(seed || i)."""
    out: list[float] = []
    i = 0
    while len(out) < count:
        block = hashlib.sha256(seed + i.to_bytes(8, "little")).digest()
        i += 1
        for off in range(0, 32, 4):
            if len(out) >= count:
                break
            u = struct.unpack_from("<I", block, off)[0]
            out.append((u / 4294967295.0) * 2.0 - 1.0)
    return out


def _xavier(seed: bytes, rows: int, cols: int) -> list[float]:
    """Fan-in scaled matrix, not a flat +/-0.02 hash dump."""
    scale = math.sqrt(6.0 / float(rows + cols))
    return [v * scale for v in _stream(seed, rows * cols)]


def _ones(n: int) -> list[float]:
    return [1.0] * n


def _pack_f32(values: list[float]) -> bytes:
    return b"".join(struct.pack("<f", v) for v in values)


def _mix_bytecode_into_embed(
    mat: list[float],
    cols: int,
    raw: bytes,
    ops: list[dict[str, Any]],
) -> None:
    """Write SPARK_BC bytes and opcode ids into embed rows 0..255."""
    for i, byte in enumerate(raw[: min(len(raw), VOCAB)]):
        base = i * cols
        if base >= len(mat):
            break
        mat[base] = (byte / 255.0) * 0.5
    for op in ops:
        row = op["op"] % VOCAB
        base = row * cols
        if base + 1 < len(mat):
            mat[base + 1] += 0.05 * (op["ip"] + 1)


def write_safetensors(
    tensors: dict[str, tuple[tuple[int, ...], bytes]],
    metadata: dict[str, str],
    dest: Path,
) -> None:
    """Write safetensors without HuggingFace libraries."""
    header: dict[str, Any] = {"__metadata__": metadata}
    offset = 0
    body = bytearray()
    for name, (shape, raw) in tensors.items():
        header[name] = {
            "dtype": "F32",
            "shape": list(shape),
            "data_offsets": [offset, offset + len(raw)],
        }
        body.extend(raw)
        offset += len(raw)
    hdr = json.dumps(header, separators=(",", ":")).encode("utf-8")
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(struct.pack("<Q", len(hdr)) + hdr + body)


def read_safetensors(
    path: str | Path,
) -> tuple[
    dict[str, str],
    dict[str, tuple[tuple[int, ...], bytes]],
]:
    """Load Spark-written safetensors (F32 only). No HuggingFace."""
    raw = Path(path).read_bytes()
    if len(raw) < 8:
        raise ValueError("truncated safetensors")
    hdr_len = struct.unpack_from("<Q", raw, 0)[0]
    end = 8 + hdr_len
    if end > len(raw):
        raise ValueError("truncated safetensors header")
    header = json.loads(raw[8:end].decode("utf-8"))
    meta_raw = header.get("__metadata__") or {}
    meta = {str(k): str(v) for k, v in meta_raw.items()}
    body = raw[end:]
    tensors: dict[str, tuple[tuple[int, ...], bytes]] = {}
    for name, info in header.items():
        if name == "__metadata__":
            continue
        if not isinstance(info, dict):
            raise ValueError("bad tensor header: %s" % name)
        dtype = info.get("dtype")
        if dtype != "F32":
            raise ValueError("unsupported dtype %s" % dtype)
        shape = tuple(int(x) for x in info["shape"])
        start, stop = info["data_offsets"]
        blob = body[int(start) : int(stop)]
        want = 4
        for dim in shape:
            want *= int(dim)
        if len(blob) != want:
            raise ValueError("tensor size mismatch: %s" % name)
        tensors[name] = (shape, bytes(blob))
    return meta, tensors


def read_safetensors_meta(path: str | Path) -> dict[str, str]:
    """Return only __metadata__ from a Spark safetensors file."""
    meta, _tensors = read_safetensors(path)
    return meta


def _add(
    tensors: dict[str, tuple[tuple[int, ...], bytes]],
    sizes: dict[str, list[int]],
    name: str,
    shape: tuple[int, ...],
    values: list[float],
) -> None:
    tensors[name] = (shape, _pack_f32(values))
    sizes[name] = list(shape)


def emit_init_weights(
    sparkbc_path: str | Path,
    dest: str | Path,
    *,
    source: str,
    command: str,
) -> dict[str, Any]:
    """Create structured init weights seeded by the full SPARK_BC file."""
    bc = load_sparkbc(sparkbc_path)
    ops = decode_ops(bc)
    arch = arch_from_bc(bc)
    dim = arch["dim"]
    vocab = arch["vocab"]
    n_kv = arch["n_kv"]
    hd = arch["head_dim"]
    mlp = arch["mlp"]
    seed0 = hashlib.sha256(bc["raw"]).digest()

    tensors: dict[str, tuple[tuple[int, ...], bytes]] = {}
    sizes: dict[str, list[int]] = {}

    embed = _xavier(seed0 + b"embed", vocab, dim)
    _mix_bytecode_into_embed(embed, dim, bc["raw"], ops)
    _add(tensors, sizes, "spark.embed.weight", (vocab, dim), embed)
    _add(
        tensors,
        sizes,
        "spark.lm_head.weight",
        (vocab, dim),
        _xavier(seed0 + b"lm", vocab, dim),
    )
    _add(tensors, sizes, "spark.final_norm.weight", (dim,), _ones(dim))

    for li in range(arch["n_layer"]):
        tag = b"L%d" % li
        p = "spark.layers.%d" % li
        _add(
            tensors,
            sizes,
            p + ".attn_norm.weight",
            (dim,),
            _ones(dim),
        )
        _add(
            tensors,
            sizes,
            p + ".q.weight",
            (dim, dim),
            _xavier(seed0 + tag + b"q", dim, dim),
        )
        _add(
            tensors,
            sizes,
            p + ".k.weight",
            (n_kv * hd, dim),
            _xavier(seed0 + tag + b"k", n_kv * hd, dim),
        )
        _add(
            tensors,
            sizes,
            p + ".v.weight",
            (n_kv * hd, dim),
            _xavier(seed0 + tag + b"v", n_kv * hd, dim),
        )
        _add(
            tensors,
            sizes,
            p + ".o.weight",
            (dim, dim),
            _xavier(seed0 + tag + b"o", dim, dim),
        )
        _add(
            tensors,
            sizes,
            p + ".mlp_norm.weight",
            (dim,),
            _ones(dim),
        )
        _add(
            tensors,
            sizes,
            p + ".mlp_up.weight",
            (mlp, dim),
            _xavier(seed0 + tag + b"up", mlp, dim),
        )
        _add(
            tensors,
            sizes,
            p + ".mlp_gate.weight",
            (mlp, dim),
            _xavier(seed0 + tag + b"gate", mlp, dim),
        )
        _add(
            tensors,
            sizes,
            p + ".mlp_down.weight",
            (dim, mlp),
            _xavier(seed0 + tag + b"down", dim, mlp),
        )

    meta = {
        "genome": "SPARK_BC",
        "factory": "Spark language",
        "sparkbc_sha256": bc["sha256"],
        "sparkbc_first_32_hex": hex_preview(bc["raw"], 32),
        "source": source,
        "command": command,
        "arch": json.dumps(arch, separators=(",", ":")),
        "derivation": (
            "full SPARK_BC bytes -> sha256 seed; Xavier/fan-in "
            "named tensors; embed rows mix magic/opcode/string bytes"
        ),
        "trained": "false",
        "served": "false",
        "goal": "init only; later train needs owner grant",
        "note": (
            "Spark-created init from SPARK_BC; not trained; "
            "TRAIN in the binary is the program, not weights"
        ),
    }
    out = Path(dest)
    write_safetensors(tensors, meta, out)
    return {
        "op": "emit_weights",
        "status": "implemented",
        "path": str(out),
        "sha256": hashlib.sha256(out.read_bytes()).hexdigest(),
        "size_bytes": out.stat().st_size,
        "arch": arch,
        "tensors": sizes,
        "n_tensors": len(sizes),
        "trained": False,
        "derivation": meta["derivation"],
        "sparkbc_sha256": bc["sha256"],
        "first_32_hex": hex_preview(bc["raw"], 32),
        "goal": "init only (later train is not a claim today)",
    }

def apply_dry_step(
    sparkbc_path: str | Path,
    dest: str | Path,
    *,
    step_n: int | None = None,
    source: str = "",
    command: str = "",
) -> dict[str, Any]:
    """Legacy dry STEP: bytecode-hash delta only (not SGD).

    Kept for unit regression. Live STEP path uses apply_sgd_step.
    """
    bc_path = Path(sparkbc_path)
    out = Path(dest)
    if not out.is_file():
        emit_init_weights(
            bc_path,
            out,
            source=source or str(bc_path),
            command=command
            or (
                "dry STEP seed from SPARK_BC "
                "(not SGD; trained=false)"
            ),
        )
    meta, tensors = read_safetensors(out)
    prev = 0
    if meta.get("step_n"):
        prev = int(meta["step_n"])
    if step_n is None:
        n = prev + 1
    else:
        n = int(step_n)
    if n < 1:
        n = 1
    if n <= prev:
        n = prev + 1

    bc = load_sparkbc(bc_path)
    seed = hashlib.sha256(
        bc["raw"] + b"dry-step" + n.to_bytes(4, "little")
    ).digest()
    u = struct.unpack_from("<I", seed, 0)[0]
    delta = (u / 4294967295.0) * 1.0e-3

    tname = "spark.embed.weight"
    if tname not in tensors:
        raise KeyError("missing tensor %s" % tname)
    shape, blob = tensors[tname]
    count = len(blob) // 4
    values = list(struct.unpack("<%df" % count, blob))
    values[0] = float(values[0]) + float(delta)
    tensors[tname] = (shape, _pack_f32(values))

    meta["step_n"] = str(n)
    meta["trained"] = "false"
    meta["served"] = "false"
    meta["op"] = "step"
    meta["not_sgd"] = "true"
    meta["sparkbc_sha256"] = bc["sha256"]
    meta["genome"] = meta.get("genome") or "SPARK_BC"
    meta["factory"] = meta.get("factory") or "Spark language"
    meta["note"] = (
        "dry STEP updated Spark-created weights; "
        "not SGD; not trained"
    )
    base_der = meta.get("derivation") or "SPARK_BC init"
    meta["derivation"] = (
        "%s; dry STEP delta on %s[0] from bytecode hash"
        % (base_der, tname)
    )
    if source:
        meta["source"] = source
    if command:
        meta["command"] = command

    write_safetensors(tensors, meta, out)
    return {
        "op": "step_weights",
        "status": "implemented",
        "path": str(out),
        "sha256": hashlib.sha256(out.read_bytes()).hexdigest(),
        "size_bytes": out.stat().st_size,
        "step_n": n,
        "delta": delta,
        "tensor": tname,
        "trained": False,
        "not_sgd": True,
        "sparkbc_sha256": bc["sha256"],
        "note": meta["note"],
    }


def _unpack_f32(blob: bytes) -> list[float]:
    """Decode little-endian F32 blob to Python floats."""
    count = len(blob) // 4
    return list(struct.unpack("<%df" % count, blob))


def _load_jsonl_pairs(path: Path) -> list[tuple[str, str]]:
    """Read user/assistant pairs from fixture dataset.jsonl."""
    pairs: list[tuple[str, str]] = []
    text = path.read_text(encoding="utf-8")
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        row = json.loads(line)
        msgs = row.get("messages") or []
        user = ""
        asst = ""
        for msg in msgs:
            role = str(msg.get("role") or "")
            content = str(msg.get("content") or "")
            if role == "user":
                user = content
            elif role == "assistant":
                asst = content
        if user and asst:
            pairs.append((user, asst))
    if not pairs:
        raise ValueError("empty train dataset: %s" % path)
    return pairs


def _mean_pool_embed(
    embed: list[float], dim: int, text: str
) -> list[float]:
    """Bag-of-bytes mean of embed rows (CPU; no GPU)."""
    raw = text.encode("utf-8") or b"\0"
    h = [0.0] * dim
    for byte in raw:
        base = (byte % VOCAB) * dim
        for j in range(dim):
            h[j] += embed[base + j]
    n = float(len(raw))
    return [v / n for v in h]


def _logits_from_w(
    w: list[float], dim: int, vocab: int, h: list[float]
) -> list[float]:
    """y = W @ h for W shaped (vocab, dim)."""
    out: list[float] = []
    for v in range(vocab):
        base = v * dim
        s = 0.0
        for j in range(dim):
            s += w[base + j] * h[j]
        out.append(s)
    return out


def _softmax(xs: list[float]) -> list[float]:
    """Numerically stable softmax."""
    m = max(xs)
    ex = [math.exp(x - m) for x in xs]
    z = sum(ex) or 1.0
    return [e / z for e in ex]


def _batch_ce(
    w: list[float],
    embed: list[float],
    dim: int,
    vocab: int,
    pairs: list[tuple[str, str]],
    *,
    train_embed: bool = False,
) -> tuple[float, list[float], list[float] | None, float]:
    """Mean CE + grads. Returns (loss, gw, g_embed|None, gnorm)."""
    gw = [0.0] * len(w)
    g_emb: list[float] | None = (
        [0.0] * len(embed) if train_embed else None
    )
    total = 0.0
    for user, asst in pairs:
        raw = user.encode("utf-8") or b"\0"
        h = _mean_pool_embed(embed, dim, user)
        target = (asst.encode("utf-8") or b"\0")[0] % vocab
        logits = _logits_from_w(w, dim, vocab, h)
        probs = _softmax(logits)
        total += -math.log(max(probs[target], 1e-12))
        dlogits = list(probs)
        dlogits[target] -= 1.0
        dh = [0.0] * dim
        for v in range(vocab):
            base = v * dim
            dv = dlogits[v]
            for j in range(dim):
                gw[base + j] += dv * h[j]
                dh[j] += dv * w[base + j]
        if g_emb is not None:
            scale = 1.0 / float(len(raw))
            for byte in raw:
                base = (byte % VOCAB) * dim
                for j in range(dim):
                    g_emb[base + j] += dh[j] * scale
    n = float(len(pairs))
    loss = total / n
    for i in range(len(gw)):
        gw[i] /= n
    if g_emb is not None:
        for i in range(len(g_emb)):
            g_emb[i] /= n
    gnorm = math.sqrt(sum(g * g for g in gw))
    if g_emb is not None:
        gnorm += math.sqrt(sum(g * g for g in g_emb))
    return loss, gw, g_emb, gnorm


def _write_checkpoint(
    path: Path,
    payload: dict[str, Any],
) -> None:
    """Write checkpoint.json next to weights (CPU SGD only)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, indent=2) + "\n",
        encoding="utf-8",
    )


def apply_sgd_step(
    sparkbc_path: str | Path,
    dest: str | Path,
    *,
    step_n: int | None = None,
    dataset: str | Path | None = None,
    lr: float = 0.08,
    inner_steps: int = 8,
    outer_steps: int = 4,
    train_embed: bool = True,
    lr_embed: float | None = None,
    checkpoint: str | Path | None = None,
    source: str = "",
    command: str = "",
) -> dict[str, Any]:
    """Multi-outer CPU SGD on Spark tensors (tiny; not beat Claude).

    Fixture JSONL → mean-pool embed → CE on lm_head (optional embed
    grads). Records a loss_curve and writes checkpoint.json. Sets
    trained=true / not_sgd=false only when loss drops. CPU only —
    never the voice GPU / RTX PRO 6000.
    """
    bc_path = Path(sparkbc_path)
    out = Path(dest)
    data_path = Path(
        dataset or "examples/fixtures/train/dataset.jsonl"
    )
    if not data_path.is_file():
        raise FileNotFoundError(
            "SGD STEP needs dataset: %s" % data_path
        )
    pairs = _load_jsonl_pairs(data_path)
    if not out.is_file():
        emit_init_weights(
            bc_path,
            out,
            source=source or str(bc_path),
            command=command
            or (
                "SGD STEP seed from SPARK_BC "
                "(CPU; not beat Claude)"
            ),
        )
    meta, tensors = read_safetensors(out)
    prev = 0
    if meta.get("step_n"):
        prev = int(meta["step_n"])
    if step_n is None:
        n = prev + 1
    else:
        n = int(step_n)
    if n < 1:
        n = 1
    if n <= prev:
        n = prev + 1

    embed_name = "spark.embed.weight"
    head_name = "spark.lm_head.weight"
    if embed_name not in tensors or head_name not in tensors:
        raise KeyError(
            "SGD STEP needs %s and %s" % (embed_name, head_name)
        )
    emb_shape, emb_blob = tensors[embed_name]
    head_shape, head_blob = tensors[head_name]
    if len(emb_shape) != 2 or len(head_shape) != 2:
        raise ValueError("unexpected tensor ranks for SGD")
    vocab = int(emb_shape[0])
    dim = int(emb_shape[1])
    if head_shape != (vocab, dim):
        raise ValueError(
            "lm_head shape %s != (%d, %d)"
            % (head_shape, vocab, dim)
        )
    embed = _unpack_f32(emb_blob)
    w = _unpack_f32(head_blob)
    before_w = list(w)
    before_e = list(embed)
    lr_e = float(lr) * 0.25 if lr_embed is None else float(lr_embed)
    n_outer = max(1, int(outer_steps))
    n_inner = max(1, int(inner_steps))
    do_embed = bool(train_embed)

    loss_before, _gw0, _ge0, g0 = _batch_ce(
        w,
        embed,
        dim,
        vocab,
        pairs,
        train_embed=do_embed,
    )
    if g0 <= 0.0:
        raise RuntimeError(
            "SGD STEP stub fail: zero grad before update"
        )

    loss_curve: list[dict[str, Any]] = [
        {"outer": 0, "loss": loss_before, "phase": "start"}
    ]
    for outer in range(n_outer):
        for _ in range(n_inner):
            loss_i, gw, g_emb, gnorm = _batch_ce(
                w,
                embed,
                dim,
                vocab,
                pairs,
                train_embed=do_embed,
            )
            if gnorm <= 0.0:
                raise RuntimeError(
                    "SGD STEP stub fail: zero grad mid-loop "
                    "(loss=%s)" % loss_i
                )
            for i in range(len(w)):
                w[i] -= float(lr) * gw[i]
            if do_embed and g_emb is not None:
                for i in range(len(embed)):
                    embed[i] -= lr_e * g_emb[i]
        loss_o, _gwo, _geo, _go = _batch_ce(
            w,
            embed,
            dim,
            vocab,
            pairs,
            train_embed=do_embed,
        )
        loss_curve.append(
            {
                "outer": outer + 1,
                "loss": loss_o,
                "phase": "after_outer",
            }
        )

    loss_after = float(loss_curve[-1]["loss"])
    moved_w = any(
        abs(w[i] - before_w[i]) > 1e-12 for i in range(len(w))
    )
    moved_e = any(
        abs(embed[i] - before_e[i]) > 1e-12
        for i in range(len(embed))
    )
    if not (moved_w or (do_embed and moved_e)):
        raise RuntimeError(
            "SGD STEP stub fail: weights unchanged"
        )
    if not (loss_after < loss_before):
        raise RuntimeError(
            "SGD STEP stub fail: loss did not drop "
            "(before=%s after=%s)" % (loss_before, loss_after)
        )

    tensors[head_name] = (head_shape, _pack_f32(w))
    if do_embed:
        tensors[embed_name] = (emb_shape, _pack_f32(embed))
    bc = load_sparkbc(bc_path)
    ckpt_path = (
        Path(checkpoint)
        if checkpoint
        else out.parent / "checkpoint.json"
    )
    meta["step_n"] = str(n)
    meta["trained"] = "true"
    meta["not_sgd"] = "false"
    meta["sgd"] = "true"
    meta["served"] = "false"
    meta["op"] = "step"
    meta["loss_before"] = "%.8g" % loss_before
    meta["loss_after"] = "%.8g" % loss_after
    meta["dataset"] = str(data_path)
    meta["dataset_n"] = str(len(pairs))
    meta["sgd_tensor"] = (
        "%s+%s" % (head_name, embed_name)
        if do_embed
        else head_name
    )
    meta["sgd_lr"] = "%.6g" % float(lr)
    meta["sgd_lr_embed"] = "%.6g" % lr_e
    meta["sgd_inner"] = str(n_inner)
    meta["sgd_outer"] = str(n_outer)
    meta["train_embed"] = "true" if do_embed else "false"
    meta["checkpoint"] = str(ckpt_path)
    meta["device"] = "cpu"
    meta["never_gpu"] = "rtx-pro-6000"
    meta["sparkbc_sha256"] = bc["sha256"]
    meta["genome"] = meta.get("genome") or "SPARK_BC"
    meta["factory"] = meta.get("factory") or "Spark language"
    meta["goal"] = (
        "multi-outer CPU SGD on Spark tensors; "
        "does not beat Claude"
    )
    meta["note"] = (
        "CPU multi-outer SGD updated lm_head"
        + ("+embed" if do_embed else "")
        + "; trained=true; not_sgd=false; not beat Claude"
    )
    base_der = meta.get("derivation") or "SPARK_BC init"
    meta["derivation"] = (
        "%s; multi-outer CPU SGD CE on %s "
        "(outer=%d inner=%d; fixture JSONL n=%d)"
        % (
            base_der,
            meta["sgd_tensor"],
            n_outer,
            n_inner,
            len(pairs),
        )
    )
    if source:
        meta["source"] = source
    if command:
        meta["command"] = command

    write_safetensors(tensors, meta, out)
    ckpt = {
        "op": "checkpoint",
        "mode": "cpu-sgd",
        "status": "implemented",
        "step_n": n,
        "loss_before": loss_before,
        "loss_after": loss_after,
        "loss_curve": loss_curve,
        "outer_steps": n_outer,
        "inner_steps": n_inner,
        "lr": float(lr),
        "lr_embed": lr_e,
        "train_embed": do_embed,
        "dataset": str(data_path),
        "dataset_n": len(pairs),
        "weights": str(out),
        "weights_sha256": hashlib.sha256(
            out.read_bytes()
        ).hexdigest(),
        "trained": True,
        "not_sgd": False,
        "sgd": True,
        "beats_claude": False,
        "device": "cpu",
        "never": "rtx-pro-6000",
        "sparkbc_sha256": bc["sha256"],
        "note": meta["note"],
    }
    _write_checkpoint(ckpt_path, ckpt)
    return {
        "op": "step_weights",
        "status": "implemented",
        "mode": "cpu-sgd",
        "path": str(out),
        "checkpoint": str(ckpt_path),
        "sha256": ckpt["weights_sha256"],
        "size_bytes": out.stat().st_size,
        "step_n": n,
        "tensor": meta["sgd_tensor"],
        "trained": True,
        "not_sgd": False,
        "sgd": True,
        "loss_before": loss_before,
        "loss_after": loss_after,
        "loss_curve": loss_curve,
        "outer_steps": n_outer,
        "inner_steps": n_inner,
        "train_embed": do_embed,
        "grad_norm_before": g0,
        "dataset": str(data_path),
        "dataset_n": len(pairs),
        "sparkbc_sha256": bc["sha256"],
        "note": meta["note"],
        "beats_claude": False,
        "device": "cpu",
    }

