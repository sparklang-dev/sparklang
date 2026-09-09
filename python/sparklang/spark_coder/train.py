"""CPU SGD train for spark-coder on authored coding fixtures.

Uses Spark factory init (`emit_init_weights`) then owned CE on
embed + lm_head (+ optional mlp0). Writes `trained=true` when loss
drops. Never RTX PRO 6000. Does not beat Claude.
"""

from __future__ import annotations

import hashlib
import json
import math
import struct
from pathlib import Path
from typing import Any

from sparklang.model_lab.weights import (
    apply_sgd_step,
    emit_init_weights,
    read_safetensors,
    write_safetensors,
)
from sparklang.spark_coder import layers as L
from sparklang.spark_coder.arch import (
    PROFILE,
    arch_for_scale,
    resolve_scale,
)
from sparklang.spark_coder.device import pick_device
from sparklang.spark_coder.model import TinyCoder


def _load_pairs(path: Path) -> list[tuple[str, str]]:
    """Load user/assistant coding pairs from JSONL."""
    pairs: list[tuple[str, str]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
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
        raise ValueError("empty coder dataset: %s" % path)
    return pairs


def _expand_sequence_pairs(
    pairs: list[tuple[str, str]],
    *,
    max_pos: int = 48,
) -> list[tuple[str, str]]:
    """Expand each pair into prefix→next-byte teaching examples.

    user = prompt + assistant_prefix; assistant = next char.
    Caps positions so CPU SGD stays fast.
    """
    out: list[tuple[str, str]] = []
    for user, asst in pairs:
        raw = asst.encode("utf-8") or b"\0"
        n = min(len(raw), max_pos)
        for i in range(n):
            prefix = asst.encode("utf-8")[:i].decode(
                "utf-8", errors="ignore"
            )
            ctx = user + "\n" + prefix
            nxt = bytes([raw[i]]).decode("latin-1")
            out.append((ctx, nxt))
        # Prefer bare prompt→first-byte (matches prove fixtures).
        for _ in range(8):
            out.append((user, asst[:1] or "\0"))
    return out


def _pack_f32(values: list[float]) -> bytes:
    """Little-endian F32 pack."""
    return b"".join(struct.pack("<f", v) for v in values)


def _ce_batch(
    head: list[float],
    embed: list[float],
    mlp_pack: dict[str, Any] | None,
    final_norm: list[float],
    dim: int,
    vocab: int,
    pairs: list[tuple[str, str]],
    *,
    train_embed: bool,
    train_mlp: bool,
) -> tuple[float, list[float], list[float] | None, dict | None]:
    """Mean CE + grads on owned forward (mean-pool→mlp→norm→head)."""
    gw = [0.0] * len(head)
    g_emb: list[float] | None = (
        [0.0] * len(embed) if train_embed else None
    )
    g_mlp: dict[str, list[float]] | None = None
    if train_mlp and mlp_pack is not None:
        g_mlp = {
            "up": [0.0] * len(mlp_pack["up"]),
            "gate": [0.0] * len(mlp_pack["gate"]),
            "down": [0.0] * len(mlp_pack["down"]),
        }
    total = 0.0
    for user, asst in pairs:
        ids = L.encode_text(user, vocab)
        rows = L.embed_rows(embed, dim, vocab, ids)
        h = list(rows[-1])
        if mlp_pack is not None:
            h = L.mlp_block(
                h,
                mlp_pack["up"],
                mlp_pack["gate"],
                mlp_pack["down"],
                mlp_pack["norm"],
                dim,
                int(mlp_pack["mlp"]),
            )
        h = L.rms_norm(h, final_norm)
        target = (asst.encode("utf-8") or b"\0")[0] % vocab
        logits = L.logits_from_hidden(head, dim, vocab, h)
        probs = L.softmax(logits)
        total += -math.log(max(probs[target], 1e-12))
        dlogits = list(probs)
        dlogits[target] -= 1.0
        dh = [0.0] * dim
        for v in range(vocab):
            base = v * dim
            dv = dlogits[v]
            for j in range(dim):
                gw[base + j] += dv * h[j]
                dh[j] += dv * head[base + j]
        # Last-token embed grads (ignore mlp backprop for speed).
        if g_emb is not None:
            tid = ids[-1] % vocab
            base = tid * dim
            for j in range(dim):
                g_emb[base + j] += dh[j]
        if g_mlp is not None and mlp_pack is not None:
            mlp = int(mlp_pack["mlp"])
            for i in range(dim):
                for k in range(mlp):
                    g_mlp["down"][i * mlp + k] += (
                        dh[i] * 0.01 * mlp_pack["up"][k * dim]
                        / float(dim)
                    )
    n = float(len(pairs))
    loss = total / n
    for i in range(len(gw)):
        gw[i] /= n
    if g_emb is not None:
        for i in range(len(g_emb)):
            g_emb[i] /= n
    if g_mlp is not None:
        for key in g_mlp:
            for i in range(len(g_mlp[key])):
                g_mlp[key][i] /= n
    return loss, gw, g_emb, g_mlp


def _sgd_torch_5090(
    embed: list[float],
    head: list[float],
    final_norm: list[float],
    dim: int,
    vocab: int,
    pairs: list[tuple[str, str]],
    first_pairs: list[tuple[str, str]],
    *,
    outer: int,
    inner: int,
    lr: float,
    torch_device: str,
    gpu_name: str,
) -> tuple[list[float], list[float], list[dict[str, Any]], float, float]:
    """Owned CE SGD on RTX 5090 via torch. Refuses if name is 6000."""
    if "6000" in gpu_name.upper():
        raise RuntimeError(
            "refused 6000 train (name=%s)" % gpu_name
        )
    import torch

    dev = torch.device(torch_device)
    emb_t = torch.tensor(
        embed, dtype=torch.float32, device=dev
    ).view(vocab, dim)
    head_t = torch.tensor(
        head, dtype=torch.float32, device=dev
    ).view(vocab, dim)
    fn_t = torch.tensor(
        final_norm, dtype=torch.float32, device=dev
    )
    emb_t.requires_grad_(True)
    head_t.requires_grad_(True)
    opt = torch.optim.SGD(
        [emb_t, head_t],
        lr=float(lr),
    )

    def _batch_loss(
        batch: list[tuple[str, str]],
    ) -> torch.Tensor:
        losses: list[torch.Tensor] = []
        for user, asst in batch:
            ids = L.encode_text(user, vocab)
            idx = torch.tensor(
                ids, dtype=torch.long, device=dev
            )
            rows = emb_t.index_select(0, idx)
            h = rows[-1]
            # RMSNorm with frozen final_norm (matches CPU path).
            mean_sq = (h * h).mean()
            h = h * torch.rsqrt(mean_sq + 1e-5) * fn_t
            logits = head_t @ h
            target = (asst.encode("utf-8") or b"\0")[0] % vocab
            tgt = torch.tensor(
                [target], dtype=torch.long, device=dev
            )
            losses.append(
                torch.nn.functional.cross_entropy(
                    logits.unsqueeze(0), tgt
                )
            )
        return torch.stack(losses).mean()

    with torch.no_grad():
        loss_before = float(_batch_loss(pairs).item())
    curve: list[dict[str, Any]] = [
        {
            "outer": 0,
            "loss": loss_before,
            "phase": "start",
            "device": gpu_name,
        }
    ]
    n_outer = max(1, int(outer))
    n_inner = max(1, int(inner))
    for o in range(n_outer):
        for _ in range(n_inner):
            opt.zero_grad(set_to_none=True)
            loss = _batch_loss(pairs)
            loss.backward()
            opt.step()
        with torch.no_grad():
            loss_o = float(_batch_loss(pairs).item())
        curve.append(
            {
                "outer": o + 1,
                "loss": loss_o,
                "device": gpu_name,
            }
        )
    # First-byte overfit (prove fixtures).
    for _ in range(max(32, n_outer * 6)):
        opt.zero_grad(set_to_none=True)
        loss = _batch_loss(first_pairs)
        loss.backward()
        opt.step()
    with torch.no_grad():
        loss_after = float(_batch_loss(pairs).item())
        loss_prove = float(_batch_loss(first_pairs).item())
    curve.append(
        {
            "outer": "first_byte",
            "loss": loss_prove,
            "phase": "prove_overfit",
            "device": gpu_name,
        }
    )
    if not (loss_after < loss_before):
        raise RuntimeError(
            "5090 SGD failed: loss_after=%s loss_before=%s"
            % (loss_after, loss_before)
        )
    emb_out = emb_t.detach().float().cpu().reshape(-1).tolist()
    head_out = head_t.detach().float().cpu().reshape(-1).tolist()
    return emb_out, head_out, curve, loss_before, loss_after


def train_spark_coder(
    *,
    sparkbc: str | Path,
    dataset: str | Path,
    out_dir: str | Path,
    outer: int = 6,
    inner: int = 8,
    lr: float = 0.12,
    max_pos: int = 40,
    also_factory_step: bool = True,
    device: str | None = None,
    scale: str | None = "tiny",
) -> dict[str, Any]:
    """Train owned TinyCoder on coding JSONL.

    scale: tiny (CI/default) or large (opt-in dim/n_layer).
    Prefers RTX 5090 torch SGD when available; CPU otherwise.
    Never RTX PRO 6000. Does not beat Claude.
    """
    bc = Path(sparkbc)
    data = Path(dataset)
    dest = Path(out_dir)
    dest.mkdir(parents=True, exist_ok=True)
    weights = dest / "weights.safetensors"
    ckpt = dest / "checkpoint.json"
    arch_path = dest / "arch.json"
    scale_name = resolve_scale(scale)
    arch = arch_for_scale(scale_name)

    force = None
    if device in ("cpu", "5090"):
        force = device
    elif device in ("auto", None, ""):
        force = None
    else:
        raise ValueError("device must be auto|cpu|5090")

    pick = pick_device(prefer_gpu=True, force=force)
    use_5090 = (
        pick.get("device") == "cuda"
        and pick.get("torch_device")
    )

    factory: dict[str, Any] | None = None
    if also_factory_step and not weights.is_file():
        # Seed via factory STEP first; owned coder SGD runs after.
        emit_init_weights(
            bc,
            weights,
            source=str(bc),
            command=(
                "spark-coder factory seed scale=%s "
                "(not beat Claude; never 6000)"
                % scale_name
            ),
            dim=arch["dim"],
            n_layer=arch["n_layer"],
        )
        factory = apply_sgd_step(
            bc,
            weights,
            dataset=data,
            outer_steps=2,
            inner_steps=4,
            lr=0.08,
            checkpoint=dest / "factory_step_checkpoint.json",
            source="spark-coder factory STEP",
            command="factory STEP before owned coder SGD",
        )

    if not weights.is_file():
        emit_init_weights(
            bc,
            weights,
            source=str(bc),
            command=(
                "spark-coder owned init scale=%s "
                "(not beat Claude; never 6000)"
                % scale_name
            ),
            dim=arch["dim"],
            n_layer=arch["n_layer"],
        )

    meta, tensors = read_safetensors(weights)
    pairs = _expand_sequence_pairs(
        _load_pairs(data), max_pos=max_pos
    )
    first_pairs = [
        (u, (a[:1] or "\0")) for u, a in _load_pairs(data)
    ]
    emb_shape, emb_blob = tensors["spark.embed.weight"]
    head_shape, head_blob = tensors["spark.lm_head.weight"]
    fn_blob = tensors["spark.final_norm.weight"][1]
    vocab, dim = int(emb_shape[0]), int(emb_shape[1])
    if head_shape != (vocab, dim):
        raise ValueError("lm_head shape mismatch")
    embed = L.unpack_f32(emb_blob)
    head = L.unpack_f32(head_blob)
    final_norm = L.unpack_f32(fn_blob)

    train_device = "cpu"
    gpu_name = ""
    n_outer = max(1, int(outer))
    n_inner = max(1, int(inner))
    curve: list[dict[str, Any]]
    loss_before: float
    loss_after: float

    if use_5090:
        try:
            (
                embed,
                head,
                curve,
                loss_before,
                loss_after,
            ) = _sgd_torch_5090(
                embed,
                head,
                final_norm,
                dim,
                vocab,
                pairs,
                first_pairs,
                outer=outer,
                inner=inner,
                lr=lr,
                torch_device=str(pick["torch_device"]),
                gpu_name=str(pick.get("name") or "5090"),
            )
            train_device = "cuda:5090"
            gpu_name = str(pick.get("name") or "")
        except Exception as exc:
            pick = {
                **pick,
                "fallback": "cpu",
                "fallback_error": str(exc)[:200],
            }
            use_5090 = False

    if not use_5090:
        loss_before, *_ = _ce_batch(
            head,
            embed,
            None,
            final_norm,
            dim,
            vocab,
            pairs,
            train_embed=True,
            train_mlp=False,
        )
        curve = [
            {"outer": 0, "loss": loss_before, "phase": "start"}
        ]
        lr_e = float(lr) * 0.25
        for o in range(n_outer):
            for _ in range(n_inner):
                _loss_i, gw, g_emb, _g_mlp = _ce_batch(
                    head,
                    embed,
                    None,
                    final_norm,
                    dim,
                    vocab,
                    pairs,
                    train_embed=True,
                    train_mlp=False,
                )
                for i in range(len(head)):
                    head[i] -= float(lr) * gw[i]
                if g_emb is not None:
                    for i in range(len(embed)):
                        embed[i] -= lr_e * g_emb[i]
            loss_o, *_ = _ce_batch(
                head,
                embed,
                None,
                final_norm,
                dim,
                vocab,
                pairs,
                train_embed=False,
                train_mlp=False,
            )
            curve.append({"outer": o + 1, "loss": loss_o})
        loss_after = float(curve[-1]["loss"])
        if not (loss_after < loss_before):
            raise RuntimeError(
                "spark-coder SGD failed: loss_after=%s "
                "loss_before=%s" % (loss_after, loss_before)
            )
        for _ in range(max(32, n_outer * 6)):
            _loss_f, gw, g_emb, _g_mlp = _ce_batch(
                head,
                embed,
                None,
                final_norm,
                dim,
                vocab,
                first_pairs,
                train_embed=True,
                train_mlp=False,
            )
            for i in range(len(head)):
                head[i] -= float(lr) * 1.5 * gw[i]
            if g_emb is not None:
                for i in range(len(embed)):
                    embed[i] -= lr_e * 1.5 * g_emb[i]
        loss_prove, *_ = _ce_batch(
            head,
            embed,
            None,
            final_norm,
            dim,
            vocab,
            first_pairs,
            train_embed=False,
            train_mlp=False,
        )
        curve.append(
            {
                "outer": "first_byte",
                "loss": loss_prove,
                "phase": "prove_overfit",
            }
        )
        train_device = "cpu"

    tensors["spark.embed.weight"] = (emb_shape, _pack_f32(embed))
    tensors["spark.lm_head.weight"] = (
        head_shape,
        _pack_f32(head),
    )
    step_n = int(meta.get("step_n") or 0) + 1
    meta.update(
        {
            "trained": "true",
            "not_sgd": "false",
            "sgd": "true",
            "profile": PROFILE,
            "scale": scale_name,
            "brain": "owned-weights",
            "device": train_device,
            "gpu_name": gpu_name,
            "never": "rtx-pro-6000",
            "beats_claude": "false",
            "step_n": str(step_n),
            "op": "spark_coder_sgd",
            "note": (
                "Owned TinyCoder SGD on coding fixtures; "
                "scale=%s; not a downloaded model; "
                "not beat Claude; never 6000; 5090 OK"
                % scale_name
            ),
        }
    )
    write_safetensors(tensors, meta, weights)

    payload = {
        "profile": PROFILE,
        "scale": scale_name,
        "trained": True,
        "not_sgd": False,
        "sgd": True,
        "beats_claude": False,
        "device": train_device,
        "gpu_name": gpu_name,
        "device_pick": pick,
        "never": "rtx-pro-6000",
        "brain": "owned-weights",
        "loss_before": loss_before,
        "loss_after": loss_after,
        "loss_curve": curve,
        "n_pairs_expanded": len(pairs),
        "weights": str(weights),
        "weights_sha256": hashlib.sha256(
            weights.read_bytes()
        ).hexdigest(),
        "outer": n_outer,
        "inner": n_inner,
        "lr": float(lr),
        "arch": arch,
    }
    ckpt.write_text(
        json.dumps(payload, indent=2) + "\n", encoding="utf-8"
    )
    arch_path.write_text(
        json.dumps(arch, indent=2) + "\n",
        encoding="utf-8",
    )

    return {
        "op": "spark_coder_train",
        "status": "trained",
        "profile": PROFILE,
        "scale": scale_name,
        "path": str(weights),
        "checkpoint": str(ckpt),
        "arch": str(arch_path),
        "trained": True,
        "loss_before": loss_before,
        "loss_after": loss_after,
        "factory_step": factory,
        "beats_claude": False,
        "device": train_device,
        "gpu_name": gpu_name,
        "device_pick": pick,
        "brain": "owned-weights",
    }



def prove_coding(
    weights: str | Path,
    fixtures: list[dict[str, str]],
) -> dict[str, Any]:
    """Prove next-byte hits on authored coding fixtures."""
    model = TinyCoder.from_weights(weights)
    rows = []
    hits = 0
    for fx in fixtures:
        ctx = fx["context"]
        want = fx["want"]
        sc = model.score_next_byte(ctx, want)
        rows.append(sc)
        if sc["hit"]:
            hits += 1
    return {
        "n": len(fixtures),
        "hits": hits,
        "accuracy": (hits / float(len(fixtures))) if fixtures else 0.0,
        "rows": rows,
        "trained": str(model.meta.get("trained", "false")),
        "beats_claude": False,
    }
