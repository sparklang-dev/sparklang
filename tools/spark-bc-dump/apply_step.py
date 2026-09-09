#!/usr/bin/env python3
"""Dry STEP weight bump for bootstrap --run-bc (not SGD)."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python"))

from sparklang.model_lab.weights import apply_dry_step


def main() -> int:
    """Apply one dry STEP update to Spark-created safetensors."""
    ap = argparse.ArgumentParser(
        description=(
            "Bump step_n + tiny bytecode-hash delta on "
            "Spark-created weights (trained=false; not SGD)"
        )
    )
    ap.add_argument("--sparkbc", required=True, help="SPARK_BC seed")
    ap.add_argument(
        "--weights",
        required=True,
        help="safetensors path to create or update",
    )
    ap.add_argument(
        "--step",
        type=int,
        default=None,
        help="target step_n (default: previous+1)",
    )
    ap.add_argument(
        "--source",
        default="",
        help="optional source label for metadata",
    )
    ap.add_argument(
        "--command",
        default="",
        help="optional command label for metadata",
    )
    args = ap.parse_args()
    result = apply_dry_step(
        args.sparkbc,
        args.weights,
        step_n=args.step,
        source=args.source,
        command=args.command,
    )
    print(json.dumps(result, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
