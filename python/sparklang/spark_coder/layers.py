"""TinyCoder layers — embed, MLP (SwiGLU-ish), RMSNorm, lm_head.

Implemented in this repo. Attention Q/K/V/O tensors may exist in
weights (factory layout); this coder forward uses mean-pool embed
→ layer-0 MLP → final_norm → lm_head (matches tip serve honesty).
CPU only. Never RTX PRO 6000.
"""

from __future__ import annotations

import math
from typing import Any


def unpack_f32(blob: bytes) -> list[float]:
    """Decode little-endian F32 blob."""
    import struct

    count = len(blob) // 4
    return list(struct.unpack("<%df" % count, blob))


def pack_f32(values: list[float]) -> bytes:
    """Encode little-endian F32 blob."""
    import struct

    return b"".join(struct.pack("<f", v) for v in values)


def embed_rows(
    embed: list[float],
    dim: int,
    vocab: int,
    ids: list[int],
) -> list[list[float]]:
    """Lookup embed rows for token ids."""
    out: list[list[float]] = []
    for tid in ids:
        t = int(tid) % vocab
        base = t * dim
        out.append(embed[base : base + dim])
    return out


def mean_pool(rows: list[list[float]], dim: int) -> list[float]:
    """Mean of token rows."""
    if not rows:
        return [0.0] * dim
    acc = [0.0] * dim
    for row in rows:
        for i in range(dim):
            acc[i] += row[i]
    n = float(len(rows))
    return [v / n for v in acc]


def rms_norm(
    x: list[float],
    w: list[float],
    eps: float = 1e-5,
) -> list[float]:
    """RMSNorm: x * w / rms(x)."""
    n = float(len(x))
    mean_sq = sum(v * v for v in x) / n
    inv = 1.0 / math.sqrt(mean_sq + eps)
    return [x[i] * inv * w[i] for i in range(len(x))]


def matvec(
    w: list[float],
    rows: int,
    cols: int,
    x: list[float],
) -> list[float]:
    """y = W @ x for W shaped (rows, cols)."""
    out: list[float] = []
    for r in range(rows):
        base = r * cols
        s = 0.0
        for c in range(cols):
            s += w[base + c] * x[c]
        out.append(s)
    return out


def silu(x: list[float]) -> list[float]:
    """SiLU activation."""
    return [v / (1.0 + math.exp(-v)) for v in x]


def mlp_block(
    hidden: list[float],
    up: list[float],
    gate: list[float],
    down: list[float],
    norm: list[float],
    dim: int,
    mlp: int,
) -> list[float]:
    """SwiGLU-style MLP residual block."""
    x = rms_norm(hidden, norm)
    u = matvec(up, mlp, dim, x)
    g = silu(matvec(gate, mlp, dim, x))
    mid = [u[i] * g[i] for i in range(mlp)]
    d = matvec(down, dim, mlp, mid)
    return [hidden[i] + d[i] for i in range(dim)]


def logits_from_hidden(
    head: list[float],
    dim: int,
    vocab: int,
    h: list[float],
) -> list[float]:
    """lm_head @ h."""
    return matvec(head, vocab, dim, h)


def softmax(xs: list[float]) -> list[float]:
    """Stable softmax."""
    m = max(xs)
    ex = [math.exp(x - m) for x in xs]
    z = sum(ex) or 1.0
    return [e / z for e in ex]


def encode_text(text: str, vocab: int = 256) -> list[int]:
    """UTF-8 bytes as token ids."""
    raw = text.encode("utf-8") or b"\0"
    return [b % vocab for b in raw]


def decode_ids(ids: list[int]) -> str:
    """Best-effort UTF-8 decode from byte ids."""
    raw = bytes(int(i) & 0xFF for i in ids)
    return raw.decode("utf-8", errors="replace")


def forward_hidden(
    tensors: dict[str, tuple[tuple[int, ...], bytes]],
    token_ids: list[int],
) -> dict[str, Any]:
    """embed last-token → final_norm (owned coder path).

    Matches 5090/CPU coder SGD (no MLP in the coding head). Factory
    MLP tensors may still exist in the safetensors layout unused.
    """
    emb_shape, emb_raw = tensors["spark.embed.weight"]
    fn_shape, fn_raw = tensors["spark.final_norm.weight"]
    vocab, dim = int(emb_shape[0]), int(emb_shape[1])
    if fn_shape != (dim,):
        raise ValueError("final_norm shape mismatch")
    embed = unpack_f32(emb_raw)
    ids = [int(t) % vocab for t in token_ids] or [0]
    rows = embed_rows(embed, dim, vocab, ids)
    hidden = list(rows[-1])
    path = "embed_last_token"
    hidden = rms_norm(hidden, unpack_f32(fn_raw))
    path += "->rms_norm"
    return {
        "token_ids": ids,
        "hidden": hidden,
        "hidden_dim": dim,
        "vocab": vocab,
        "mlp0": False,
        "path": path,
        "embed": embed,
    }
