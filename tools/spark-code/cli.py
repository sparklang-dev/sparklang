#!/usr/bin/env python3
"""spark-code — CLI for the owned Spark coding model.

Train / generate / prove / tool-loop using TinyCoder weights written
and trained in this repo. Prefers RTX 5090; never 6000. Not beat Claude.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python"))

from sparklang.spark_coder.model import TinyCoder
from sparklang.spark_coder.tools_loop import (
    find_bootstrap,
    tool_loop_complete,
)
from sparklang.spark_coder.train import (
    prove_coding,
    train_spark_coder,
)

DEFAULT_BC = "docs/examples/spark-train-step.sparkbc"
DEFAULT_DATA = "examples/fixtures/coder/dataset.jsonl"
DEFAULT_OUT = "models/spark-coder"


def _cmd_train(args: argparse.Namespace) -> int:
    """Train owned TinyCoder weights."""
    result = train_spark_coder(
        sparkbc=args.sparkbc,
        dataset=args.dataset,
        out_dir=args.out,
        outer=args.outer,
        inner=args.inner,
        lr=args.lr,
        also_factory_step=not args.skip_factory_step,
        device=args.device,
        scale=args.scale,
    )
    print(json.dumps(result, indent=2))
    return 0 if result.get("trained") else 1


def _cmd_scales(_args: argparse.Namespace) -> int:
    """Print tiny vs large honesty table as JSON."""
    from sparklang.spark_coder.arch import scale_table

    print(
        json.dumps(
            {
                "ok": True,
                "scales": scale_table(),
                "beats_claude": False,
                "never": "rtx-pro-6000",
                "prefer_device": "rtx-5090",
            },
            indent=2,
        )
    )
    return 0


def _cmd_generate(args: argparse.Namespace) -> int:
    """Greedy generate from owned weights."""
    weights = Path(args.weights)
    if not weights.is_file():
        print(
            json.dumps(
                {
                    "ok": False,
                    "error": "weights missing",
                    "path": str(weights),
                    "hint": "run: spark-code train",
                }
            )
        )
        return 2
    model = TinyCoder.from_weights(weights)
    out = model.generate(args.prompt, max_new=args.max_new)
    print(json.dumps(out, indent=2))
    return 0


def _cmd_prove(args: argparse.Namespace) -> int:
    """Prove next-byte coding fixtures."""
    fixtures = json.loads(
        Path(args.fixtures).read_text(encoding="utf-8")
    )
    result = prove_coding(args.weights, fixtures)
    print(json.dumps(result, indent=2))
    need = float(args.min_acc)
    ok = (
        result["accuracy"] >= need
        and str(result.get("trained")).lower()
        in ("true", "1", "yes")
    )
    return 0 if ok else 1


def _cmd_tool_loop(args: argparse.Namespace) -> int:
    """Owned model + compile verify on candidate .spark files."""
    weights = Path(args.weights)
    if not weights.is_file():
        print(
            json.dumps(
                {
                    "ok": False,
                    "error": "weights missing",
                    "path": str(weights),
                }
            )
        )
        return 2
    model = TinyCoder.from_weights(weights)
    cands = [Path(p) for p in args.candidate]
    boot = find_bootstrap(ROOT)
    if args.bootstrap:
        boot = Path(args.bootstrap)
    result = tool_loop_complete(
        model,
        task=args.task,
        candidate_sources=cands,
        work_dir=Path(args.work),
        bootstrap=boot,
    )
    print(json.dumps(result, indent=2))
    return 0 if result.get("ok") else 1


def _cmd_status(args: argparse.Namespace) -> int:
    """Show weights meta / arch."""
    weights = Path(args.weights)
    if not weights.is_file():
        print(
            json.dumps(
                {
                    "ok": False,
                    "status": "no_weights",
                    "path": str(weights),
                    "brain": "owned-weights",
                }
            )
        )
        return 2
    model = TinyCoder.from_weights(weights)
    print(
        json.dumps(
            {
                "ok": True,
                "path": str(weights),
                "trained": model.meta.get("trained"),
                "scale": model.meta.get("scale", "tiny"),
                "profile": model.meta.get("profile", "spark-coder"),
                "brain": model.meta.get("brain", "owned-weights"),
                "arch": model.arch_json(),
                "beats_claude": False,
                "prefer_device": "rtx-5090",
                "never": "rtx-pro-6000",
            },
            indent=2,
        )
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    """CLI entry for spark-code."""
    ap = argparse.ArgumentParser(
        prog="spark-code",
        description=(
            "Owned Spark coding model (TinyCoder). "
            "Not Claude/HF. Prefer RTX 5090; never 6000. "
            "Does not beat Claude."
        ),
    )
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_tr = sub.add_parser("train", help="SGD train (tiny|large)")
    p_tr.add_argument("--sparkbc", default=DEFAULT_BC)
    p_tr.add_argument("--dataset", default=DEFAULT_DATA)
    p_tr.add_argument("--out", default=DEFAULT_OUT)
    p_tr.add_argument("--outer", type=int, default=6)
    p_tr.add_argument("--inner", type=int, default=8)
    p_tr.add_argument("--lr", type=float, default=0.12)
    p_tr.add_argument(
        "--scale",
        default="tiny",
        choices=("tiny", "large"),
        help="tiny=CI/default; large=opt-in dim64/n_layer4",
    )
    p_tr.add_argument(
        "--device",
        default="auto",
        choices=("auto", "cpu", "5090"),
        help="auto prefers RTX 5090; never 6000",
    )
    p_tr.add_argument(
        "--skip-factory-step",
        action="store_true",
        help="skip apply_sgd_step factory companion",
    )
    p_tr.set_defaults(func=_cmd_train)

    p_sc = sub.add_parser(
        "scales", help="honesty table tiny vs large"
    )
    p_sc.set_defaults(func=_cmd_scales)

    p_gen = sub.add_parser("generate", help="greedy generate")
    p_gen.add_argument(
        "--weights",
        default=str(Path(DEFAULT_OUT) / "weights.safetensors"),
    )
    p_gen.add_argument("--prompt", required=True)
    p_gen.add_argument("--max-new", type=int, default=64)
    p_gen.set_defaults(func=_cmd_generate)

    p_pr = sub.add_parser("prove", help="fixture next-byte prove")
    p_pr.add_argument(
        "--weights",
        default=str(Path(DEFAULT_OUT) / "weights.safetensors"),
    )
    p_pr.add_argument(
        "--fixtures",
        default="examples/fixtures/coder/prove.json",
    )
    p_pr.add_argument("--min-acc", type=float, default=0.5)
    p_pr.set_defaults(func=_cmd_prove)

    p_tl = sub.add_parser(
        "tool-loop", help="rank candidates + compile"
    )
    p_tl.add_argument(
        "--weights",
        default=str(Path(DEFAULT_OUT) / "weights.safetensors"),
    )
    p_tl.add_argument("--task", required=True)
    p_tl.add_argument(
        "--candidate",
        action="append",
        required=True,
        help="candidate .spark path (repeatable)",
    )
    p_tl.add_argument("--work", default="out/spark-coder/tool-loop")
    p_tl.add_argument("--bootstrap", default="")
    p_tl.set_defaults(func=_cmd_tool_loop)

    p_st = sub.add_parser("status", help="weights status")
    p_st.add_argument(
        "--weights",
        default=str(Path(DEFAULT_OUT) / "weights.safetensors"),
    )
    p_st.set_defaults(func=_cmd_status)

    args = ap.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
