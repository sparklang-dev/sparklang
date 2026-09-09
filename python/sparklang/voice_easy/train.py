"""CPU SGD train for owned voice-easy STT + TTS heads.

Optional device record prefers RTX 5090; never 6000.
Large scale can refuse when only 6000 is visible.
"""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any

from sparklang.voice_easy.device import (
    VoiceDeviceError,
    pick_voice_device,
)
from sparklang.voice_easy.fixtures import prep_fixtures
from sparklang.voice_easy.model import VoiceEasyModel
from sparklang.voice_easy.scales import resolve_scale


def _softmax(logits: list[float]) -> list[float]:
    """Stable softmax."""
    m = max(logits) if logits else 0.0
    ex = [math.exp(v - m) for v in logits]
    s = sum(ex) or 1.0
    return [v / s for v in ex]


def _train_step_stt(
    model: VoiceEasyModel,
    feats: list[float],
    target: int,
    lr: float,
) -> float:
    """One CE step on STT head; mutate weights in place."""
    bins = model.feat_bins
    dim = model.dim
    n = model.n_phrases
    x = list(feats[:bins]) + [0.0] * max(0, bins - len(feats))
    w1 = model.stt_w[: bins * dim]
    w2 = model.stt_w[bins * dim : bins * dim + dim * n]
    # Forward
    pre = [0.0] * dim
    h = [0.0] * dim
    for j in range(dim):
        s = 0.0
        for i in range(bins):
            s += x[i] * w1[i * dim + j]
        pre[j] = s
        h[j] = math.tanh(s)
    logits = [0.0] * n
    for k in range(n):
        s = 0.0
        for j in range(dim):
            s += h[j] * w2[j * n + k]
        logits[k] = s
    probs = _softmax(logits)
    loss = -math.log(max(1e-9, probs[target]))
    # dL/dlogit
    dlog = list(probs)
    dlog[target] -= 1.0
    gw2 = [0.0] * (dim * n)
    dh = [0.0] * dim
    for k in range(n):
        for j in range(dim):
            gw2[j * n + k] += h[j] * dlog[k]
            dh[j] += w2[j * n + k] * dlog[k]
    gw1 = [0.0] * (bins * dim)
    for j in range(dim):
        dpre = dh[j] * (1.0 - h[j] * h[j])
        for i in range(bins):
            gw1[i * dim + j] += x[i] * dpre
    # SGD
    for i in range(len(w1)):
        w1[i] -= lr * gw1[i]
    for i in range(len(w2)):
        w2[i] -= lr * gw2[i]
    model.stt_w = w1 + w2
    return loss


def _train_step_tts(
    model: VoiceEasyModel,
    phrase_id: int,
    target_freq: float,
    lr: float,
) -> float:
    """L2 on TTS freq param toward fixture tone."""
    n = model.n_phrases
    pid = max(0, min(n - 1, int(phrase_id)))
    # Inverse of freq = 180 + (tanh(f)+1)*200 → target tanh
    # freq in [180, 580] roughly
    want = (target_freq - 180.0) / 200.0 - 1.0
    want = max(-0.999, min(0.999, want))
    # artanh
    target_f = 0.5 * math.log((1.0 + want) / (1.0 - want))
    cur = model.tts_w[pid * 2]
    err = cur - target_f
    model.tts_w[pid * 2] = cur - lr * err
    # gentle amp toward mid
    model.tts_w[pid * 2 + 1] -= lr * 0.1 * model.tts_w[pid * 2 + 1]
    return 0.5 * err * err


def train_voice_easy(
    *,
    out_dir: Path,
    fixture_dir: Path,
    scale_name: str = "tiny",
    device: str = "auto",
    dry: bool = False,
) -> dict[str, Any]:
    """Prep fixtures, train owned heads, write weights + checkpoint."""
    scale = resolve_scale(scale_name)
    if dry:
        # CI dry: clamp large; tiny still needs enough steps for
        # STT acc ≥ 0.5 on fixture tones.
        scale = dict(scale)
        if scale["name"] == "large":
            scale["steps"] = min(int(scale["steps"]), 24)
        else:
            scale["steps"] = max(int(scale["steps"]), 40)
        scale["dry"] = True

    try:
        pick = pick_voice_device(scale=scale, force=device)
    except VoiceDeviceError as exc:
        return {
            "ok": False,
            "trained": False,
            "error": str(exc),
            "beats_claude": False,
            "never": "rtx-pro-6000",
            "scale": scale["name"],
        }

    manifest = prep_fixtures(
        fixture_dir,
        n_phrases=int(scale["n_phrases"]),
        bins=int(scale["feat_bins"]),
    )
    model = VoiceEasyModel.init_from_scale(scale)
    pairs = list(manifest["pairs"])
    steps = int(scale["steps"])
    lr = float(scale["lr"])
    losses: list[float] = []
    for step in range(steps):
        total = 0.0
        for row in pairs:
            feats = list(row["features"])
            pid = int(row["id"])
            total += _train_step_stt(model, feats, pid, lr)
            total += _train_step_tts(
                model, pid, float(row["freq_hz"]), lr
            )
        losses.append(total / max(1, len(pairs)))

    loss_before = float(losses[0]) if losses else 0.0
    loss_after = float(losses[-1]) if losses else 0.0
    trained = loss_after < loss_before
    model.meta["trained"] = "true" if trained else "false"
    model.meta["scale"] = scale["name"]
    model.meta["device"] = str(pick.get("device"))
    model.meta["torch_device"] = str(pick.get("torch_device") or "")
    model.meta["dry"] = "true" if dry else "false"
    weights = model.save(out_dir)

    # STT accuracy on train fixtures
    correct = 0
    for row in pairs:
        pred = model.stt_predict(list(row["features"]))
        if pred == int(row["id"]):
            correct += 1
    acc = correct / max(1, len(pairs))

    ckpt = {
        "profile": "spark-voice-easy",
        "scale": scale["name"],
        "steps": steps,
        "lr": lr,
        "loss_before": loss_before,
        "loss_after": loss_after,
        "loss_curve": losses[:: max(1, len(losses) // 8)] or losses,
        "stt_acc": acc,
        "trained": trained,
        "device": pick,
        "vram_gi_hint": scale["vram_gi_hint"],
        "beats_claude": False,
        "never": "rtx-pro-6000",
        "brain": "owned-weights",
        "dry": dry,
        "weights": str(weights),
        "note": scale.get("note"),
    }
    (Path(out_dir) / "checkpoint.json").write_text(
        json.dumps(ckpt, indent=2) + "\n",
        encoding="utf-8",
    )
    return {
        "ok": trained and acc >= 0.5,
        "trained": trained,
        "stt_acc": acc,
        "loss_before": loss_before,
        "loss_after": loss_after,
        "scale": scale["name"],
        "device": pick,
        "weights": str(weights),
        "beats_claude": False,
        "never": "rtx-pro-6000",
        "dry": dry,
    }
