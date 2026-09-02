#!/usr/bin/env python3
"""spark-abstain companion — dry fixtures or live head train/attach/ask.

Usage:
  spark-abstain --dry|--live --stmt-file PATH --out PATH
  spark-abstain --live train --dataset … --out …
  spark-abstain --live attach --model … --weights … --out …
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
from sparklang.abstain.dry import dry_result, dumps_compact
from sparklang.abstain.gate import GateConfig, select_before_sample
from sparklang.abstain.parse import parse_head_stmt
from sparklang.abstain.train import train_abstain_head


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
        # Live without HF: refuse inventing — dry-style gate only
        # if SPARK_ABSTAIN_STUB=1; else require hidden via env path.
        stub = os.environ.get("SPARK_ABSTAIN_STUB", "") == "1"
        if stub:
            return dry_result(fields)
        raise SystemExit(
            "head ask live needs local hidden path "
            "(or SPARK_ABSTAIN_STUB=1 for fixture gate)"
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
        choices=("train", "attach", "gate"),
    )
    ap.add_argument("--dataset")
    ap.add_argument("--model")
    ap.add_argument("--weights")
    ap.add_argument("--kind", default="internal")
    ap.add_argument("--hidden-dim", type=int)
    ap.add_argument("--threshold", type=float, default=0.7)
    ap.add_argument("--idk", default="I don't know.")
    ap.add_argument("--p", type=float)
    args = ap.parse_args(argv)
    live = bool(args.live)

    if args.cmd == "gate":
        if args.p is None:
            raise SystemExit("gate needs --p")
        d = select_before_sample(
            args.p,
            GateConfig(threshold=args.threshold, idk=args.idk),
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

    if not args.stmt_file:
        raise SystemExit("need --stmt-file or train|attach|gate")
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
