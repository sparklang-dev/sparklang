#!/usr/bin/env python3
"""CPU multi-outer SGD STEP weight update for bootstrap --run-bc."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python"))

from sparklang.model_lab.weights import apply_sgd_step


def main() -> int:
    """Apply multi-outer CPU SGD STEP to Spark-created safetensors."""
    ap = argparse.ArgumentParser(
        description=(
            "CPU multi-outer SGD on Spark lm_head(+embed+attn0) "
            "from fixture JSONL (trained=true; not_sgd=false; "
            "no frontier-parity claim; never 6000)"
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
        help="SGD learning rate for lm_head",
    )
    ap.add_argument(
        "--inner",
        type=int,
        default=8,
        help="inner SGD iterations per outer",
    )
    ap.add_argument(
        "--outer",
        type=int,
        default=4,
        help="outer epochs per STEP (loss curve points)",
    )
    ap.add_argument(
        "--no-train-embed",
        action="store_true",
        help="update lm_head only (default also trains embed)",
    )
    ap.add_argument(
        "--no-train-attn",
        action="store_true",
        help="skip layer-0 attention grads (mean-pool CE only)",
    )
    ap.add_argument(
        "--checkpoint",
        default="",
        help="checkpoint.json path (default: beside weights)",
    )
    ap.add_argument(
        "--dim",
        type=int,
        default=None,
        help=(
            "optional d_model when seeding new weights "
            "(8..128, %% n_head); CI keeps default"
        ),
    )
    ap.add_argument(
        "--n-layer",
        type=int,
        default=None,
        dest="n_layer",
        help=(
            "optional n_layers when seeding new weights "
            "(1..8); CI keeps default"
        ),
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
        outer_steps=args.outer,
        train_embed=not args.no_train_embed,
        train_attn=not args.no_train_attn,
        checkpoint=args.checkpoint or None,
        source=args.source,
        command=args.command,
        dim=args.dim,
        n_layer=args.n_layer,
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
    if "beats_claude" in result:
        print(
            "error: beats_claude field is removed from tool output",
            file=sys.stderr,
        )
        return 2
    print(json.dumps(result, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
