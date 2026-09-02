#!/usr/bin/env python3
"""spark-abstain companion — dry fixtures or live head train/attach/ask.

Usage:
  spark-abstain --dry|--live --stmt-file PATH --out PATH
  spark-abstain --live train --dataset … --out …
  spark-abstain --live export --dataset … --out … [--model|dim]
  spark-abstain --live eval --dataset … [--weights|--train-out]
  spark-abstain --live attach --model … --weights … --out …
  spark-abstain --live ask --prompt … --weights … [--hidden|/HF]
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# Repo-root python/ on path when run as ./spark-abstain
_ROOT = Path(__file__).resolve().parents[2]
_PY = _ROOT / "python"
if _PY.is_dir() and str(_PY) not in sys.path:
    sys.path.insert(0, str(_PY))

from sparklang.abstain.attach import attach_head
from sparklang.abstain.corpus import validate_corpus
from sparklang.abstain.dry import dry_result, dumps_compact
from sparklang.abstain.eval import run_heldout_eval
from sparklang.abstain.export import export_hiddens
from sparklang.abstain.gate import GateConfig, select_before_sample
from sparklang.abstain.generate import live_ask
from sparklang.abstain.inventable import outer_verify_or_refuse
from sparklang.abstain.parse import parse_head_stmt
from sparklang.abstain.train import (
    mark_head_quality,
    train_abstain_head,
)


def _write_out(text: str, out: str | None) -> None:
    if out:
        Path(out).parent.mkdir(parents=True, exist_ok=True)
        Path(out).write_text(text + "\n", encoding="utf-8")
        return
    sys.stdout.write(text)
    if not text.endswith("\n"):
        sys.stdout.write("\n")


def _run_stmt(fields: dict, live: bool) -> dict:
    op = fields["op"]
    if not live:
        return dry_result(fields)
    if op == "train":
        ds = fields.get("dataset")
        out = fields.get("out")
        if not ds or not out:
            raise SystemExit(
                "head train needs dataset and out"
            )
        return train_abstain_head(
            ds,
            out,
            kind=str(fields.get("kind") or "internal"),
            hidden_dim=(
                int(fields["hidden_dim"])
                if "hidden_dim" in fields
                else None
            ),
        )
    if op == "attach":
        model = fields.get("model")
        weights = fields.get("weights")
        out = fields.get("out") or "out/heads/manifest.json"
        if not model or not weights:
            raise SystemExit(
                "head attach needs model and weights"
            )
        return attach_head(
            model,
            weights,
            out,
            kind=str(fields.get("kind") or "internal"),
            threshold=float(fields.get("threshold") or 0.7),
            idk=str(fields.get("idk") or "I don't know."),
        )
    if op == "abstain":
        # Live declare: require weights on disk; echo ready JSON.
        weights = fields.get("weights")
        if not weights or not Path(weights).is_file():
            raise SystemExit(
                f"head abstain live needs weights file: {weights}"
            )
        return {
            "op": "head_abstain",
            "mode": "live",
            "kind": fields.get("kind") or "internal",
            "threshold": float(fields.get("threshold") or 0.7),
            "idk": fields.get("idk") or "I don't know.",
            "model": fields.get("model") or "",
            "weights": weights,
            "state": "ready",
        }
    if op == "ask":
        # Stub = dry heuristics only. Live = real p(abstain|h).
        stub = os.environ.get("SPARK_ABSTAIN_STUB", "") == "1"
        if stub:
            out = dry_result(fields)
            out["mode"] = "stub"
            return out
        prompt = str(fields.get("prompt") or "")
        return live_ask(
            prompt,
            weights=os.environ.get("SPARK_ABSTAIN_WEIGHTS") or None,
            manifest=(
                os.environ.get("SPARK_ABSTAIN_MANIFEST") or None
            ),
            model=os.environ.get("SPARK_ABSTAIN_MODEL") or None,
            hidden_path=(
                os.environ.get("SPARK_ABSTAIN_HIDDEN") or None
            ),
            threshold=(
                float(fields["threshold"])
                if "threshold" in fields
                else None
            ),
            idk=(
                str(fields["idk"]) if "idk" in fields else None
            ),
        )
    raise SystemExit(f"unknown op {op}")


def main(argv: list[str] | None = None) -> int:
    """CLI entry."""
    ap = argparse.ArgumentParser(prog="spark-abstain")
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--dry", action="store_true")
    mode.add_argument("--live", action="store_true")
    ap.add_argument("--stmt-file")
    ap.add_argument("--out")
    ap.add_argument(
        "cmd",
        nargs="?",
        choices=(
            "train",
            "attach",
            "gate",
            "ask",
            "export",
            "eval",
            "validate-corpus",
            "outer-verify",
            "mark-quality",
        ),
    )
    ap.add_argument("--dataset")
    ap.add_argument("--model")
    ap.add_argument("--weights")
    ap.add_argument("--manifest")
    ap.add_argument("--hidden")
    ap.add_argument("--prompt")
    ap.add_argument("--kind", default="internal")
    ap.add_argument("--hidden-dim", type=int)
    ap.add_argument(
        "--source",
        default="auto",
        choices=("auto", "toy", "synthetic", "hf"),
        help=(
            "export feature source: toy (CI), synthetic "
            "(dim-matched wide), hf (--model), auto"
        ),
    )
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--threshold", type=float, default=0.7)
    ap.add_argument("--idk", default="I don't know.")
    ap.add_argument(
        "--holdout",
        type=float,
        default=0.2,
        help="held-out fraction for eval (default 0.2)",
    )
    ap.add_argument(
        "--train-out",
        help="eval: write retrained head weights here",
    )
    ap.add_argument(
        "--split-dir",
        help="eval: write train.jsonl + heldout.jsonl here",
    )
    ap.add_argument("--steps", type=int, default=200)
    ap.add_argument("--p", type=float)
    ap.add_argument("--entropy", type=float, default=None)
    ap.add_argument("--entropy-max", type=float, default=None)
    ap.add_argument("--margin", type=float, default=None)
    ap.add_argument("--margin-min", type=float, default=None)
    ap.add_argument("--max-new-tokens", type=int, default=32)
    ap.add_argument(
        "--sot-ok",
        action="store_true",
        help="outer verify: SoT/HTTP expect already passed",
    )
    ap.add_argument(
        "--outer-verify",
        action="store_true",
        help="run inventable outer verify-or-refuse helper",
    )
    args = ap.parse_args(argv)
    live = bool(args.live)

    if args.cmd == "validate-corpus":
        if not args.dataset:
            raise SystemExit("validate-corpus needs --dataset")
        result = validate_corpus(args.dataset)
        _write_out(dumps_compact(result), args.out)
        return 0

    if args.cmd == "export":
        if not live:
            raise SystemExit("export needs --live")
        if not args.dataset or not args.out:
            raise SystemExit("export needs --dataset and --out")
        result = export_hiddens(
            args.dataset,
            args.out,
            model=args.model,
            hidden_dim=args.hidden_dim,
            seed=int(args.seed),
            kind=str(args.kind or "internal"),
            source=str(args.source or "auto"),
        )
        _write_out(dumps_compact(result), None)
        return 0

    if args.cmd == "gate":
        if args.p is None:
            raise SystemExit("gate needs --p")
        d = select_before_sample(
            args.p,
            GateConfig(
                threshold=args.threshold,
                idk=args.idk,
                entropy_max=args.entropy_max,
                margin_min=args.margin_min,
            ),
            entropy=args.entropy,
            margin=args.margin,
        )
        payload = {
            "abstain": d.abstain,
            "p_abstain": d.p_abstain,
            "text": d.text,
            "halted": d.halted,
            "reason": d.reason,
        }
        _write_out(dumps_compact(payload), args.out)
        return 0

    if args.cmd == "outer-verify":
        if not args.prompt:
            raise SystemExit("outer-verify needs --prompt")
        result = outer_verify_or_refuse(
            args.prompt,
            sot_ok=bool(args.sot_ok),
            idk=args.idk,
        )
        _write_out(dumps_compact(result), args.out)
        return 0

    if args.cmd == "mark-quality":
        if not live:
            raise SystemExit("mark-quality needs --live")
        if not args.weights:
            raise SystemExit("mark-quality needs --weights")
        stamp = os.environ.get(
            "SPARK_ABSTAIN_QUALITY_STAMP", "hf_backbone_trained"
        )
        result = mark_head_quality(args.weights, stamp)
        _write_out(dumps_compact(result), args.out)
        return 0

    if args.cmd == "eval":
        if not live:
            raise SystemExit("eval needs --live")
        if not args.dataset:
            raise SystemExit("eval needs --dataset")
        result = run_heldout_eval(
            args.dataset,
            weights=args.weights,
            train_out=args.train_out,
            holdout_frac=float(args.holdout),
            seed=int(args.seed),
            threshold=float(args.threshold),
            idk=str(args.idk),
            hidden_dim=args.hidden_dim,
            steps=int(args.steps),
            split_dir=args.split_dir,
            out=args.out,
        )
        # Always echo metrics; --out also stamps the JSON file.
        _write_out(dumps_compact(result), None)
        return 0

    if args.cmd == "train":
        fields = {
            "op": "train",
            "dataset": args.dataset,
            "out": args.out or args.weights,
            "kind": args.kind,
        }
        if args.hidden_dim is not None:
            fields["hidden_dim"] = args.hidden_dim
        result = _run_stmt(fields, live)
        _write_out(dumps_compact(result), None)
        return 0

    if args.cmd == "attach":
        fields = {
            "op": "attach",
            "model": args.model,
            "weights": args.weights,
            "out": args.out,
            "kind": args.kind,
            "threshold": args.threshold,
            "idk": args.idk,
        }
        result = _run_stmt(fields, live)
        _write_out(dumps_compact(result), None)
        return 0

    if args.cmd == "ask":
        if not args.prompt:
            raise SystemExit("ask needs --prompt")
        if not live:
            result = dry_result(
                {
                    "op": "ask",
                    "prompt": args.prompt,
                    "idk": args.idk,
                }
            )
            _write_out(dumps_compact(result), args.out)
            return 0
        # Fixture gate only — never invents a model / alias.
        if os.environ.get("SPARK_ABSTAIN_STUB", "") == "1":
            result = dry_result(
                {
                    "op": "ask",
                    "prompt": args.prompt,
                    "idk": args.idk,
                }
            )
            result["mode"] = "stub"
            _write_out(dumps_compact(result), args.out)
            return 0
        # Propagate CLI paths into env for live_ask resolution.
        if args.weights:
            os.environ["SPARK_ABSTAIN_WEIGHTS"] = args.weights
        if args.manifest:
            os.environ["SPARK_ABSTAIN_MANIFEST"] = args.manifest
        if args.model:
            os.environ["SPARK_ABSTAIN_MODEL"] = args.model
        if args.hidden:
            os.environ["SPARK_ABSTAIN_HIDDEN"] = args.hidden
        result = live_ask(
            args.prompt,
            weights=args.weights,
            manifest=args.manifest,
            model=args.model,
            hidden_path=args.hidden,
            threshold=args.threshold,
            idk=args.idk,
            max_new_tokens=args.max_new_tokens,
            entropy_max=args.entropy_max,
            margin_min=args.margin_min,
            entropy=args.entropy,
            margin=args.margin,
            outer_verify=bool(args.outer_verify),
            sot_ok=bool(args.sot_ok),
        )
        _write_out(dumps_compact(result), args.out)
        return 0

    if not args.stmt_file:
        raise SystemExit(
            "need --stmt-file or "
            "train|export|eval|attach|gate|ask|validate-corpus"
        )
    stmt = Path(args.stmt_file).read_text(encoding="utf-8")
    # First non-comment line
    line = ""
    for raw in stmt.splitlines():
        s = raw.strip()
        if s and not s.startswith("#"):
            line = s
            break
    if not line:
        raise SystemExit("empty stmt-file")
    fields = parse_head_stmt(line)
    result = _run_stmt(fields, live)
    text = dumps_compact(result)
    _write_out(text, args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
