#!/usr/bin/env python3
"""spark-model-lab — reverse local HF config; dry fixtures.

Live reverse never downloads, never loads tensors, never trains.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT / "python") not in sys.path:
    sys.path.insert(0, str(ROOT / "python"))

from sparklang.model_lab.reverse import reverse_local

DRY_REVERSE = {
    "op": "reverse",
    "mode": "dry-run",
    "target": "fixtures/tiny-lm",
    "architecture": "Qwen3ForCausalLM",
    "hidden_size": 64,
    "num_hidden_layers": 2,
    "num_attention_heads": 4,
    "vocab_size": 256,
    "model_type": "qwen3",
    "tensors": [
        "model.embed_tokens.weight",
        "lm_head.weight",
    ],
    "source": "examples/fixtures/models/tiny-lm/config.json",
    "keep_special_training": True,
    "note": (
        "inspect local published config/index only — "
        "not closed weights, not a new foundation LLM"
    ),
}


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="spark-model-lab")
    p.add_argument(
        "--dry",
        "--dry-run",
        dest="dry",
        action="store_true",
        help="fixture JSON only",
    )
    p.add_argument("--live", action="store_true", help="read local files")
    p.add_argument("verb", choices=["reverse", "inspect"])
    p.add_argument(
        "--model",
        default="examples/fixtures/models/tiny-lm",
        help="local HF dir (config.json)",
    )
    args = p.parse_args(argv)
    live = bool(args.live) and not args.dry
    if live:
        payload = reverse_local(args.model)
    else:
        payload = dict(DRY_REVERSE)
        payload["target"] = args.model
    json.dump(payload, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
