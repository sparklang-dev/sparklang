"""Layer-0 causal attention for tiny CPU SGD / serve / eval.

Last-query multi-head (GQA) attention over a short byte sequence.
CPU only — never the voice GPU / RTX PRO 6000. Not a production LLM.
"""

from __future__ import annotations

import math
from typing import Any


def rms_norm(x: list[float], w: list[float], eps: float = 1e-5) -> list[float]:
    """Elementwise RMSNorm."""
    if len(x) != len(w):
        raise ValueError("norm size mismatch")
    mean_sq = sum(v * v for v in x) / float(len(x))
    inv = 1.0 / math.sqrt(mean_sq + eps)
    return [x[i] * inv * w[i] for i in range(len(x))]


def matvec(
    weight: list[float],
    rows: int,
    cols: int,
    x: list[float],
) -> list[float]:
    """y = W @ x for W shaped (rows, cols)."""
    if len(x) != cols:
        raise ValueError("matvec width mismatch")
    out: list[float] = []
    for r in range(rows):
        base = r * cols
        s = 0.0
        for c in range(cols):
            s += weight[base + c] * x[c]
        out.append(s)
    return out


def softmax(xs: list[float]) -> list[float]:
    """Numerically stable softmax."""
    m = max(xs)
    ex = [math.exp(x - m) for x in xs]
    z = sum(ex) or 1.0
    return [e / z for e in ex]


def embed_rows(
    embed: list[float],
    dim: int,
    vocab: int,
    ids: list[int],
) -> list[list[float]]:
    """Lookup embed rows for token ids (vocab-clamped)."""
    rows: list[list[float]] = []
    for tid in ids:
        idx = int(tid) % vocab
        base = idx * dim
        rows.append(embed[base : base + dim])
    return rows


def _split_heads(
    vec: list[float],
    n_head: int,
    hd: int,
) -> list[list[float]]:
    """Split flat vector into n_head chunks of hd."""
    out: list[list[float]] = []
    for h in range(n_head):
        base = h * hd
        out.append(vec[base : base + hd])
    return out


def _kv_head(q_head: int, n_head: int, n_kv: int) -> int:
    """Map query head index to KV head (GQA)."""
    return (q_head * n_kv) // n_head


def attn_last_forward(
    xs: list[list[float]],
    attn_norm: list[float],
    wq: list[float],
    wk: list[float],
    wv: list[float],
    wo: list[float],
    *,
    dim: int,
    n_head: int,
    n_kv: int,
) -> tuple[list[float], dict[str, Any]]:
    """Causal last-query MHA residual. Returns (y, cache)."""
    if not xs:
        raise ValueError("empty sequence for attention")
    hd = dim // n_head
    if hd * n_head != dim:
        raise ValueError("dim not divisible by n_head")
    kv_dim = n_kv * hd
    t_len = len(xs)
    xn = [rms_norm(xs[t], attn_norm) for t in range(t_len)]
    q_flat = matvec(wq, dim, dim, xn[-1])
    qs = _split_heads(q_flat, n_head, hd)
    ks: list[list[list[float]]] = []
    vs: list[list[list[float]]] = []
    for t in range(t_len):
        k_flat = matvec(wk, kv_dim, dim, xn[t])
        v_flat = matvec(wv, kv_dim, dim, xn[t])
        ks.append(_split_heads(k_flat, n_kv, hd))
        vs.append(_split_heads(v_flat, n_kv, hd))
    scale = 1.0 / math.sqrt(float(hd))
    ctx_heads: list[list[float]] = []
    attn_w: list[list[float]] = []
    for h in range(n_head):
        kv_h = _kv_head(h, n_head, n_kv)
        scores = [
            scale
            * sum(qs[h][i] * ks[t][kv_h][i] for i in range(hd))
            for t in range(t_len)
        ]
        aw = softmax(scores)
        attn_w.append(aw)
        ctx = [0.0] * hd
        for t in range(t_len):
            a = aw[t]
            for i in range(hd):
                ctx[i] += a * vs[t][kv_h][i]
        ctx_heads.append(ctx)
    concat: list[float] = []
    for h in range(n_head):
        concat.extend(ctx_heads[h])
    proj = matvec(wo, dim, dim, concat)
    y = [xs[-1][i] + proj[i] for i in range(dim)]
    cache: dict[str, Any] = {
        "xs": xs,
        "xn": xn,
        "qs": qs,
        "ks": ks,
        "vs": vs,
        "attn_w": attn_w,
        "concat": concat,
        "proj": proj,
        "q_flat": q_flat,
        "dim": dim,
        "n_head": n_head,
        "n_kv": n_kv,
        "hd": hd,
        "scale": scale,
        "attn_norm": attn_norm,
        "wq": wq,
        "wk": wk,
        "wv": wv,
        "wo": wo,
    }
    return y, cache


def attn_last_backward(
    dy: list[float],
    cache: dict[str, Any],
) -> dict[str, list[float] | list[list[float]]]:
    """Backprop last-query MHA. Returns grads + dxs list."""
    dim = int(cache["dim"])
    n_head = int(cache["n_head"])
    n_kv = int(cache["n_kv"])
    hd = int(cache["hd"])
    scale = float(cache["scale"])
    t_len = len(cache["xs"])
    kv_dim = n_kv * hd
    wq = cache["wq"]
    wk = cache["wk"]
    wv = cache["wv"]
    wo = cache["wo"]
    xs = cache["xs"]
    xn = cache["xn"]
    qs = cache["qs"]
    ks = cache["ks"]
    vs = cache["vs"]
    attn_w = cache["attn_w"]
    concat = cache["concat"]

    # residual: y = x_last + Wo @ concat
    dx_last = list(dy)
    d_concat = [0.0] * dim
    g_wo = [0.0] * (dim * dim)
    for r in range(dim):
        base = r * dim
        dv = dy[r]
        for c in range(dim):
            g_wo[base + c] += dv * concat[c]
            d_concat[c] += dv * wo[base + c]

    d_ctx = _split_heads(d_concat, n_head, hd)
    g_wq = [0.0] * (dim * dim)
    g_wk = [0.0] * (kv_dim * dim)
    g_wv = [0.0] * (kv_dim * dim)
    dxn = [[0.0] * dim for _ in range(t_len)]
    d_q_flat = [0.0] * dim

    for h in range(n_head):
        kv_h = _kv_head(h, n_head, n_kv)
        aw = attn_w[h]
        d_ctx_h = d_ctx[h]
        # ctx = sum_t a[t] * v[t]
        d_a = [0.0] * t_len
        d_v_heads = [[0.0] * hd for _ in range(t_len)]
        for t in range(t_len):
            a = aw[t]
            for i in range(hd):
                d_v_heads[t][i] += a * d_ctx_h[i]
                d_a[t] += d_ctx_h[i] * vs[t][kv_h][i]
        # softmax backward
        s = sum(aw[t] * d_a[t] for t in range(t_len))
        d_scores = [aw[t] * (d_a[t] - s) for t in range(t_len)]
        d_q = [0.0] * hd
        for t in range(t_len):
            ds = d_scores[t] * scale
            for i in range(hd):
                d_q[i] += ds * ks[t][kv_h][i]
                # d k
                # accumulate into flat g_wk via dxn path later
            # dK from score: ds * q
            d_k = [ds * qs[h][i] for i in range(hd)]
            # write d_k into g_wk / dxn via matvec bwd for this t
            # k_flat = Wk @ xn[t]; only kv_h slice
            for i in range(hd):
                row = kv_h * hd + i
                base = row * dim
                for c in range(dim):
                    g_wk[base + c] += d_k[i] * xn[t][c]
                    dxn[t][c] += d_k[i] * wk[base + c]
            for i in range(hd):
                row = kv_h * hd + i
                base = row * dim
                dv = d_v_heads[t][i]
                for c in range(dim):
                    g_wv[base + c] += dv * xn[t][c]
                    dxn[t][c] += dv * wv[base + c]
        for i in range(hd):
            d_q_flat[h * hd + i] += d_q[i]

    # q_flat = Wq @ xn[-1]
    for r in range(dim):
        base = r * dim
        dv = d_q_flat[r]
        for c in range(dim):
            g_wq[base + c] += dv * xn[-1][c]
            dxn[-1][c] += dv * wq[base + c]

    # RMSNorm backward (attn_norm treated constant / no grad)
    dxs = [[0.0] * dim for _ in range(t_len)]
    for t in range(t_len):
        dxs[t] = _rms_norm_bwd(xs[t], cache["attn_norm"], dxn[t])
    for i in range(dim):
        dxs[-1][i] += dx_last[i]
    return {
        "g_wq": g_wq,
        "g_wk": g_wk,
        "g_wv": g_wv,
        "g_wo": g_wo,
        "dxs": dxs,
    }


def _rms_norm_bwd(
    x: list[float],
    w: list[float],
    dy: list[float],
    eps: float = 1e-5,
) -> list[float]:
    """RMSNorm backward w.r.t. x (w fixed)."""
    n = float(len(x))
    mean_sq = sum(v * v for v in x) / n
    inv = 1.0 / math.sqrt(mean_sq + eps)
    # y_i = x_i * inv * w_i
    dx = [0.0] * len(x)
    d_inv = 0.0
    for i in range(len(x)):
        dx[i] += dy[i] * inv * w[i]
        d_inv += dy[i] * x[i] * w[i]
    # inv = (mean_sq+eps)^-0.5
    d_mean_sq = d_inv * (-0.5) * (mean_sq + eps) ** -1.5
    for i in range(len(x)):
        dx[i] += d_mean_sq * (2.0 * x[i] / n)
    return dx


def logits_from_hidden(
    w: list[float],
    dim: int,
    vocab: int,
    h: list[float],
) -> list[float]:
    """lm_head @ h."""
    return matvec(w, vocab, dim, h)


def predict_next_id(
    tensors: dict[str, tuple[tuple[int, ...], bytes]],
    token_ids: list[int],
    *,
    unpack,
) -> tuple[int, dict[str, Any]]:
    """Greedy next-id via embed→attn0→final_norm→lm_head."""
    embed_shape, embed_raw = tensors["spark.embed.weight"]
    head_shape, head_raw = tensors["spark.lm_head.weight"]
    norm_shape, norm_raw = tensors["spark.final_norm.weight"]
    vocab, dim = int(embed_shape[0]), int(embed_shape[1])
    if head_shape != (vocab, dim):
        raise ValueError("lm_head shape mismatch")
    if norm_shape != (dim,):
        raise ValueError("final_norm shape mismatch")
    p = "spark.layers.0"
    need = (
        p + ".attn_norm.weight",
        p + ".q.weight",
        p + ".k.weight",
        p + ".v.weight",
        p + ".o.weight",
    )
    if any(k not in tensors for k in need):
        raise KeyError("layer-0 attention tensors missing")
    # Factory init uses n_head=4 when dim divisible by 4.
    k_shape = tensors[need[2]][0]
    kv_rows = int(k_shape[0])
    n_head = 4 if dim % 4 == 0 else 1
    hd = dim // n_head
    n_kv = max(1, kv_rows // hd)

    embed = unpack(embed_raw)
    ids = [int(t) % vocab for t in token_ids] or [0]
    xs = embed_rows(embed, dim, vocab, ids)
    y, _cache = attn_last_forward(
        xs,
        unpack(tensors[need[0]][1]),
        unpack(tensors[need[1]][1]),
        unpack(tensors[need[2]][1]),
        unpack(tensors[need[3]][1]),
        unpack(tensors[need[4]][1]),
        dim=dim,
        n_head=n_head,
        n_kv=n_kv,
    )
    y = rms_norm(y, unpack(norm_raw))
    logits = logits_from_hidden(unpack(head_raw), dim, vocab, y)
    argmax = max(range(vocab), key=lambda i: logits[i])
    return argmax, {
        "attn0": True,
        "path": "embed->attn0->rms_norm->lm_head",
        "n_head": n_head,
        "n_kv": n_kv,
        "seq_len": len(ids),
    }
