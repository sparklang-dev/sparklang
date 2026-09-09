"""Piece-of-cake voice-easy pipeline: env → fixtures → train → prove."""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path
from typing import Any

from sparklang.voice_easy.roundtrip import prove_roundtrip
from sparklang.voice_easy.scales import resolve_scale
from sparklang.voice_easy.train import train_voice_easy


def check_env(*, dry: bool = False) -> dict[str, Any]:
    """Lightweight env check — no secrets, never print keys."""
    root = Path(__file__).resolve().parents[3]
    py = sys.version_info
    spark_stt = (root / "spark-stt-tts").is_file() or (
        root / "tools" / "voice" / "spark_stt_tts.c"
    ).is_file()
    return {
        "ok": True,
        "python": "%d.%d.%d" % (py.major, py.minor, py.micro),
        "cwd": str(Path.cwd()),
        "repo_root_guess": str(root),
        "spark_stt_tts_present": spark_stt,
        "voice_scale_env": os.environ.get("VOICE_SCALE", ""),
        "dry": dry,
        "cuda_visible": os.environ.get("CUDA_VISIBLE_DEVICES", ""),
        "note": (
            "No API keys required for dry/tiny. "
            "External STT/TTS sidecars optional later "
            "(SPARK_STT_CMD / SPARK_TTS_CMD / net gates)."
        ),
        "never": "rtx-pro-6000",
        "beats_claude": False,
    }


def run_easy(
    *,
    root: Path | None = None,
    scale: str = "tiny",
    device: str = "auto",
    dry: bool = False,
    out_dir: Path | None = None,
    fixture_dir: Path | None = None,
) -> dict[str, Any]:
    """One-shot happy path for voice model train + STT/TTS dry prove."""
    root = Path(root) if root else Path.cwd()
    scale_cfg = resolve_scale(scale)
    if dry and scale_cfg["name"] == "large":
        # Dry CI stays tiny unless operator insists on large dry.
        # Allow large+dry for local smoke, but note VRAM/time.
        pass

    env = check_env(dry=dry)
    out = Path(out_dir) if out_dir else root / "models" / "spark-voice-easy"
    fix = (
        Path(fixture_dir)
        if fixture_dir
        else root / "out" / "voice_easy" / "fixtures"
    )
    prove_out = root / "out" / "voice_easy" / "roundtrip"

    if out.exists() and (out / "weights.safetensors").exists():
        # Fresh train each easy run
        for name in (
            "weights.safetensors",
            "checkpoint.json",
            "arch.json",
        ):
            p = out / name
            if p.exists():
                p.unlink()

    if fix.exists():
        shutil.rmtree(fix)

    train = train_voice_easy(
        out_dir=out,
        fixture_dir=fix,
        scale_name=scale_cfg["name"],
        device=device,
        dry=dry,
    )
    if not train.get("ok") and train.get("error"):
        return {
            "ok": False,
            "phase": "train",
            "env": env,
            "train": train,
            "beats_claude": False,
            "never": "rtx-pro-6000",
        }

    prove = prove_roundtrip(
        weights=Path(train["weights"]),
        fixture_dir=fix,
        out_dir=prove_out,
    )
    ok = bool(train.get("ok")) and bool(prove.get("ok"))
    return {
        "ok": ok,
        "phase": "done",
        "env": env,
        "train": train,
        "prove": prove,
        "commands": {
            "easy": "./spark-voice easy --dry --device auto",
            "large": (
                "./spark-voice easy --scale large --device auto"
            ),
            "test": "make test-voice-easy",
        },
        "beats_claude": False,
        "never": "rtx-pro-6000",
        "honesty": (
            "Tiny/large owned heads — not ElevenLabs/Kokoro "
            "replacement overnight"
        ),
    }
