#!/usr/bin/env python3
"""spark-voice — real voice-easy CLI (open weights, offline).

STT: Whisper via faster-whisper (MIT weights, CT2 repack).
TTS: Kokoro-82M via kokoro-onnx (Apache-2.0 weights).
Weights fetch once (``fetch``), then every path runs offline.
CPU int8 default; RTX 5090 optional for the large lane; the
RTX PRO 6000 is voice-serving only and is never used.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python"))

from sparklang.voice_easy.device import VoiceDeviceError
from sparklang.voice_easy.eval_real import run_roundtrip_eval
from sparklang.voice_easy.pipeline import check_env, run_easy
from sparklang.voice_easy.scales import SCALES, resolve_scale
from sparklang.voice_easy.stt_real import (
    stt_model_dir,
    stt_weights_present,
)
from sparklang.voice_easy.tts_real import (
    TTS_MODEL_ONNX,
    TTS_VOICES_BIN,
    tts_weights_present,
)

FETCH_SCRIPT = ROOT / "tools" / "spark-voice" / "fetch_models.py"


def _cmd_easy(args: argparse.Namespace) -> int:
    """Env → real STT eval → real TTS roundtrip eval."""
    scale = args.scale
    if scale is None and args.dry:
        scale = "tiny"
    try:
        result = run_easy(
            root=ROOT,
            scale=scale or resolve_scale(None)["name"],
            device=args.device,
            dry=bool(args.dry),
        )
    except VoiceDeviceError as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, indent=2))
        return 2
    print(json.dumps(result, indent=2))
    return 0 if result.get("ok") else 1


def _cmd_fetch(args: argparse.Namespace) -> int:
    """Fetch (or --check) the pinned open-weight model files."""
    cmd = [sys.executable, str(FETCH_SCRIPT)]
    if args.check:
        cmd.append("--check")
    return subprocess.call(cmd, cwd=str(ROOT))


def _cmd_train(args: argparse.Namespace) -> int:
    """Honest no-train stub: weights are pretrained; fetch + eval."""
    result = {
        "ok": True,
        "trained": False,
        "note": (
            "voice-easy no longer trains toy heads. STT/TTS are "
            "pretrained open weights (Whisper MIT / Kokoro "
            "Apache-2.0). Run `./spark-voice fetch` once, then "
            "`./spark-voice easy --scale large` for the measured "
            "eval."
        ),
        "stt_weights": {
            "tiny": stt_weights_present("tiny"),
            "large-v3-turbo": stt_weights_present("large-v3-turbo"),
        },
        "tts_weights": tts_weights_present(),
        "never": "rtx-pro-6000",
    }
    print(json.dumps(result, indent=2))
    return 0


def _cmd_prove(args: argparse.Namespace) -> int:
    """Real roundtrip: TTS synthesize → STT transcribe → WER/CER."""
    scale = resolve_scale(args.scale)
    if not tts_weights_present() or not stt_weights_present(
        str(scale["stt_variant"])
    ):
        print(
            json.dumps(
                {
                    "ok": False,
                    "status": "skipped_no_weights",
                    "hint": "run: ./spark-voice fetch",
                },
                indent=2,
            )
        )
        return 2
    device = "cpu"
    if args.device in ("auto", "5090"):
        pick = None
        try:
            from sparklang.voice_easy.device import pick_voice_device

            pick = pick_voice_device(scale=scale, force=args.device)
        except VoiceDeviceError as exc:
            print(json.dumps({"ok": False, "error": str(exc)}, indent=2))
            return 2
        if pick.get("device") == "cuda":
            device = "cuda"
    result = run_roundtrip_eval(
        n_utts=int(scale["roundtrip_utts"]),
        stt_variant=str(scale["stt_variant"]),
        device=device,
        out_dir=Path(args.out),
    )
    print(json.dumps(result, indent=2))
    return 0 if result.get("ok") else 1


def _dir_size(path: Path) -> int:
    """Total bytes under a dir (0 when missing)."""
    if not path.is_dir():
        return 0
    return sum(p.stat().st_size for p in path.rglob("*") if p.is_file())


def _cmd_status(args: argparse.Namespace) -> int:
    """Show fetched weights, sizes, and last eval report."""
    del args
    report = ROOT / "out" / "voice_easy" / "eval" / "eval_report.json"
    status = {
        "ok": True,
        "stt": {
            v: {
                "present": stt_weights_present(v),
                "dir": str(stt_model_dir(v)),
                "bytes": _dir_size(stt_model_dir(v)),
            }
            for v in ("tiny", "large-v3-turbo")
        },
        "tts": {
            "present": tts_weights_present(),
            "model": str(TTS_MODEL_ONNX),
            "voices": str(TTS_VOICES_BIN),
            "bytes": _dir_size(TTS_MODEL_ONNX.parent),
        },
        "last_eval_report": (
            str(report) if report.is_file() else None
        ),
        "scales": {name: cfg["note"] for name, cfg in SCALES.items()},
        "weights": "pretrained-open (Whisper MIT / Kokoro Apache-2.0)",
        "never": "rtx-pro-6000",
    }
    print(json.dumps(status, indent=2))
    return 0


def _cmd_env(args: argparse.Namespace) -> int:
    """Print env check JSON."""
    print(json.dumps(check_env(dry=bool(args.dry)), indent=2))
    return 0


def main(argv: list[str] | None = None) -> int:
    """CLI entry for spark-voice."""
    ap = argparse.ArgumentParser(
        prog="spark-voice",
        description=(
            "Spark voice-easy on real open weights (Whisper STT + "
            "Kokoro TTS). Fetch once, then offline. CPU default; "
            "5090 optional; never the RTX PRO 6000."
        ),
    )
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_easy = sub.add_parser(
        "easy",
        help="env check → real STT WER eval → TTS roundtrip eval",
    )
    p_easy.add_argument(
        "--dry",
        action="store_true",
        help="CI-friendly path (default scale tiny; loud skip when "
        "weights are not fetched)",
    )
    p_easy.add_argument(
        "--device",
        default="auto",
        choices=("auto", "cpu", "5090"),
        help="auto prefers RTX 5090 when free; never 6000",
    )
    p_easy.add_argument(
        "--scale",
        default=None,
        choices=("tiny", "large"),
        help="tiny=CI smoke; large=real measurement (VOICE_SCALE too)",
    )
    p_easy.set_defaults(func=_cmd_easy)

    p_fetch = sub.add_parser(
        "fetch", help="fetch pinned open-weight models (once)"
    )
    p_fetch.add_argument(
        "--check",
        action="store_true",
        help="verify pinned files only; no network",
    )
    p_fetch.set_defaults(func=_cmd_fetch)

    p_tr = sub.add_parser(
        "train",
        help="honest no-train stub (pretrained weights; see fetch)",
    )
    p_tr.set_defaults(func=_cmd_train)

    p_pr = sub.add_parser(
        "prove", help="real TTS→STT roundtrip with WER/CER"
    )
    p_pr.add_argument("--out", default="out/voice_easy/roundtrip")
    p_pr.add_argument(
        "--device",
        default="auto",
        choices=("auto", "cpu", "5090"),
    )
    p_pr.add_argument(
        "--scale",
        default=None,
        choices=("tiny", "large"),
    )
    p_pr.set_defaults(func=_cmd_prove)

    p_st = sub.add_parser("status", help="weights + eval status")
    p_st.set_defaults(func=_cmd_status)

    p_env = sub.add_parser("env", help="env check (no secrets)")
    p_env.add_argument("--dry", action="store_true")
    p_env.set_defaults(func=_cmd_env)

    args = ap.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
