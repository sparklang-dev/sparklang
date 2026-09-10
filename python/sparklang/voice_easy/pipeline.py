"""Voice-easy pipeline: env → real STT eval → real TTS roundtrip.

Backed by pretrained open weights (Whisper via faster-whisper,
Kokoro via kokoro-onnx) — fetched once, then fully offline. There
is no training step and no synthetic fixture audio anywhere in this
pipeline.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any

from sparklang.voice_easy.eval_real import (
    LJSPEECH_ROOT,
    run_roundtrip_eval,
    run_stt_eval,
)
from sparklang.voice_easy.scales import resolve_scale
from sparklang.voice_easy.stt_real import (
    STT_MODELS_ROOT,
    stt_weights_present,
)
from sparklang.voice_easy.tts_real import (
    TTS_MODELS_ROOT,
    tts_weights_present,
)

FETCH_HINT = "python3 tools/spark-voice/fetch_models.py"


def check_env(*, dry: bool = False) -> dict[str, Any]:
    """Lightweight env check — no secrets, never print keys."""
    root = Path(__file__).resolve().parents[3]
    py = sys.version_info
    return {
        "ok": True,
        "python": "%d.%d.%d" % (py.major, py.minor, py.micro),
        "cwd": str(Path.cwd()),
        "repo_root_guess": str(root),
        "stt_models_root": str(STT_MODELS_ROOT),
        "tts_models_root": str(TTS_MODELS_ROOT),
        "stt_weights": {
            "tiny": stt_weights_present("tiny"),
            "large-v3-turbo": stt_weights_present("large-v3-turbo"),
        },
        "tts_weights": tts_weights_present(),
        "ljspeech_present": (LJSPEECH_ROOT / "metadata.csv").is_file(),
        "voice_scale_env": os.environ.get("VOICE_SCALE", ""),
        "dry": dry,
        "cuda_visible": os.environ.get("CUDA_VISIBLE_DEVICES", ""),
        "note": (
            "Pretrained open weights (Whisper MIT / Kokoro "
            "Apache-2.0), fetched once, then offline. No API keys."
        ),
        "never": "rtx-pro-6000",
    }


def _weights_missing(scale: dict[str, Any]) -> list[str]:
    """List which fetched weights are absent for this scale."""
    missing: list[str] = []
    if not stt_weights_present(str(scale["stt_variant"])):
        missing.append("stt:%s" % scale["stt_variant"])
    if not tts_weights_present():
        missing.append("tts:kokoro-v1.0")
    return missing


def run_easy(
    *,
    root: Path | None = None,
    scale: str = "tiny",
    device: str = "auto",
    dry: bool = False,
    out_dir: Path | None = None,
    fixture_dir: Path | None = None,
) -> dict[str, Any]:
    """Real happy path: STT WER eval + TTS→STT roundtrip eval.

    ``fixture_dir`` is accepted for CLI compatibility and ignored —
    the pipeline evaluates on real LJSpeech audio, never fixtures.
    """
    del fixture_dir  # fixtures are gone by design
    root = Path(root) if root else Path.cwd()
    scale_cfg = resolve_scale(scale)
    env = check_env(dry=dry)
    out = (
        Path(out_dir)
        if out_dir
        else root / "out" / "voice_easy" / "eval"
    )
    out.mkdir(parents=True, exist_ok=True)

    missing = _weights_missing(scale_cfg)
    if missing:
        # Loud skip, never a fake green (spark-eval convention).
        result = {
            "ok": dry,
            "status": "skipped_no_weights",
            "missing": missing,
            "hint": "fetch once, then offline: %s" % FETCH_HINT,
            "env": env,
            "scale": scale_cfg["name"],
            "never": "rtx-pro-6000",
        }
        (out / "eval_report.json").write_text(
            json.dumps(result, indent=2) + "\n", encoding="utf-8"
        )
        return result

    stt_device = "cpu"
    if device in ("auto", "5090"):
        from sparklang.voice_easy.device import pick_voice_device

        pick = pick_voice_device(scale=scale_cfg, force=device)
        if pick.get("device") == "cuda":
            stt_device = "cuda"

    stt_report = run_stt_eval(
        n_clips=int(scale_cfg["stt_clips"]),
        variant=str(scale_cfg["stt_variant"]),
        device=stt_device,
    )
    roundtrip = run_roundtrip_eval(
        n_utts=int(scale_cfg["roundtrip_utts"]),
        stt_variant=str(scale_cfg["stt_variant"]),
        device=stt_device,
        out_dir=root / "out" / "voice_easy" / "roundtrip",
    )
    ok = bool(stt_report["ok"]) and bool(roundtrip["ok"])
    result = {
        "ok": ok,
        "status": "ran",
        "phase": "done",
        "env": env,
        "scale": scale_cfg["name"],
        "stt_eval": {
            k: v for k, v in stt_report.items() if k != "details"
        },
        "roundtrip": {
            k: v for k, v in roundtrip.items() if k != "details"
        },
        "report_json": str(out / "eval_report.json"),
        "commands": {
            "easy": "./spark-voice easy --device auto",
            "large": "./spark-voice easy --scale large --device auto",
            "test": "make test-voice-easy",
        },
        "never": "rtx-pro-6000",
        "honesty": (
            "Open-weight models (Whisper MIT, Kokoro Apache-2.0), "
            "not trained by us; numbers are measured WER/CER on "
            "held-out LJSpeech — no parity claims vs proprietary "
            "services."
        ),
    }
    full = dict(result)
    full["stt_eval"] = stt_report
    full["roundtrip"] = roundtrip
    (out / "eval_report.json").write_text(
        json.dumps(full, indent=2) + "\n", encoding="utf-8"
    )
    return result
