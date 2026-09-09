#!/usr/bin/env python3
"""CPU SGD STEP weight update for bootstrap --run-bc."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python"))

from sparklang.model_lab.weights import apply_sgd_step


def main() -> int:
    """Apply one real CPU SGD STEP to Spark-created safetensors."""
    ap = argparse.ArgumentParser(
        description=(
            "CPU SGD on Spark lm_head from fixture JSONL "
            "(trained=true; not_sgd=false; not beat Claude)"
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
        "--dataset",
        default="examples/fixtures/train/dataset.jsonl",
        help="JSONL train fixture (user/assistant pairs)",
    )
    ap.add_argument(
        "--lr",
        type=float,
        default=0.08,
        help="SGD learning rate",
    )
    ap.add_argument(
        "--inner",
        type=int,
        default=12,
        help="inner SGD iterations per STEP",
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
    result = apply_sgd_step(
        args.sparkbc,
        args.weights,
        step_n=args.step,
        dataset=args.dataset,
        lr=args.lr,
        inner_steps=args.inner,
        source=args.source,
        command=args.command,
    )
    if result.get("not_sgd") is not False:
        print(
            "error: SGD STEP did not clear not_sgd",
            file=sys.stderr,
        )
        return 2
    if result.get("trained") is not True:
        print(
            "error: SGD STEP did not set trained=true",
            file=sys.stderr,
        )
        return 2
    if not (
        result["loss_after"] < result["loss_before"]
    ):
        print(
            "error: SGD STEP loss did not drop",
            file=sys.stderr,
        )
        return 2
    print(json.dumps(result, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
