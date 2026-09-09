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
