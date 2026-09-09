#!/usr/bin/env python3
"""spark-voice — piece-of-cake voice train / STT / TTS CLI.

Owned tiny or large heads. Prefer RTX 5090; never 6000.
Not ElevenLabs. Does not beat Claude. No API keys in git.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python"))

from sparklang.voice_easy.device import VoiceDeviceError
from sparklang.voice_easy.model import VoiceEasyModel
from sparklang.voice_easy.pipeline import check_env, run_easy
from sparklang.voice_easy.roundtrip import prove_roundtrip
from sparklang.voice_easy.scales import SCALES, resolve_scale
from sparklang.voice_easy.train import train_voice_easy

DEFAULT_OUT = "models/spark-voice-easy"
DEFAULT_FIX = "out/voice_easy/fixtures"


def _cmd_easy(args: argparse.Namespace) -> int:
    """Env → fixtures → train → STT/TTS dry prove."""
    scale = args.scale
    if scale is None and not args.dry:
        scale = None  # resolve from env
    elif scale is None:
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


def _cmd_train(args: argparse.Namespace) -> int:
    """Train owned voice-easy heads."""
    result = train_voice_easy(
        out_dir=Path(args.out),
        fixture_dir=Path(args.fixtures),
        scale_name=args.scale or resolve_scale(None)["name"],
        device=args.device,
        dry=bool(args.dry),
    )
    print(json.dumps(result, indent=2))
    if result.get("error"):
        return 2
    return 0 if result.get("ok") else 1


def _cmd_prove(args: argparse.Namespace) -> int:
    """STT + TTS dry round-trip."""
    result = prove_roundtrip(
        weights=Path(args.weights),
        fixture_dir=Path(args.fixtures),
        out_dir=Path(args.out),
    )
    print(json.dumps(result, indent=2))
    return 0 if result.get("ok") else 1


def _cmd_status(args: argparse.Namespace) -> int:
    """Show weights / scale honesty."""
    weights = Path(args.weights)
    if not weights.is_file():
        print(
            json.dumps(
                {
                    "ok": False,
                    "status": "no_weights",
                    "path": str(weights),
                    "hint": "run: ./spark-voice easy --dry",
                    "scales": list(SCALES),
                    "beats_claude": False,
                    "never": "rtx-pro-6000",
                },
                indent=2,
            )
        )
        return 2
    model = VoiceEasyModel.load(weights)
    print(
        json.dumps(
            {
                "ok": True,
                "path": str(weights),
                "trained": model.meta.get("trained"),
                "scale": model.meta.get("scale"),
                "dim": model.dim,
                "n_phrases": model.n_phrases,
                "beats_claude": False,
                "never": "rtx-pro-6000",
                "brain": "owned-weights",
                "vram_gi_hint": model.meta.get("vram_gi_hint"),
            },
            indent=2,
        )
    )
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
            "Owned Spark voice-easy train / STT / TTS. "
            "Tiny (CI) or large (opt-in). Prefer 5090; never 6000. "
            "Not beat Claude."
        ),
    )
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_easy = sub.add_parser(
        "easy",
        help="check env → fixtures → train → STT/TTS dry prove",
    )
    p_easy.add_argument(
        "--dry",
        action="store_true",
        help="CI-friendly dry path (default scale tiny)",
    )
    p_easy.add_argument(
        "--device",
        default="auto",
        choices=("auto", "cpu", "5090"),
        help="auto prefers RTX 5090; never 6000",
    )
    p_easy.add_argument(
        "--scale",
        default=None,
        choices=("tiny", "large"),
        help="tiny=CI demo; large=opt-in (VOICE_SCALE also)",
    )
    p_easy.set_defaults(func=_cmd_easy)

    p_tr = sub.add_parser("train", help="train owned heads")
    p_tr.add_argument("--out", default=DEFAULT_OUT)
    p_tr.add_argument("--fixtures", default=DEFAULT_FIX)
    p_tr.add_argument("--dry", action="store_true")
    p_tr.add_argument(
        "--device",
        default="auto",
        choices=("auto", "cpu", "5090"),
    )
    p_tr.add_argument(
        "--scale",
        default=None,
        choices=("tiny", "large"),
    )
    p_tr.set_defaults(func=_cmd_train)

    p_pr = sub.add_parser("prove", help="STT/TTS dry round-trip")
    p_pr.add_argument(
        "--weights",
        default=str(Path(DEFAULT_OUT) / "weights.safetensors"),
    )
    p_pr.add_argument("--fixtures", default=DEFAULT_FIX)
    p_pr.add_argument("--out", default="out/voice_easy/roundtrip")
    p_pr.set_defaults(func=_cmd_prove)

    p_st = sub.add_parser("status", help="weights status")
    p_st.add_argument(
        "--weights",
        default=str(Path(DEFAULT_OUT) / "weights.safetensors"),
    )
    p_st.set_defaults(func=_cmd_status)

    p_env = sub.add_parser("env", help="env check (no secrets)")
    p_env.add_argument("--dry", action="store_true")
    p_env.set_defaults(func=_cmd_env)

    args = ap.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
