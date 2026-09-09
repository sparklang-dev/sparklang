#!/usr/bin/env python3
"""Dump real SPARK_BC and emit the builder stub.

Reads a file produced by ./spark-bootstrap --compile. Does not invent hex.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT / "python") not in sys.path:
    sys.path.insert(0, str(ROOT / "python"))

from sparklang.model_lab.bc_dump import format_dump, load_sparkbc
from sparklang.model_lab.builder import emit_base, emit_serve, emit_stub


def main(argv: list[str] | None = None) -> int:
    """Dump a .sparkbc file or emit the builder stub JSON."""
    p = argparse.ArgumentParser(prog="spark-bc-dump")
    p.add_argument("sparkbc", help="path to a real .sparkbc")
    p.add_argument("--source", default="", help="origin .spark path")
    p.add_argument("--command", default="", help="compile command used")
    p.add_argument("--label", default="SPARK_BC dump")
    p.add_argument("-o", "--out", help="write dump text here")
    p.add_argument(
        "--stub",
        action="store_true",
        help="emit builder stub JSON instead of text dump",
    )
    p.add_argument(
        "--weights",
        help="write Spark-created init safetensors here",
    )
    p.add_argument(
        "--serve",
        help=(
            "write SERVE dir after tiny CPU forward "
            "(not production LLM)"
        ),
    )
    p.add_argument(
        "--serve-weights",
        help="optional safetensors for --serve (else init)",
    )
    args = p.parse_args(argv)
    src = args.source or args.sparkbc
    cmd = args.command or "(already compiled)"
    if args.serve:
        payload = emit_serve(
            args.sparkbc,
            args.serve,
            source=src,
            command=cmd,
            weights_path=args.serve_weights,
        )
        text = json.dumps(payload, indent=2) + "\n"
    elif args.weights:
        payload = emit_base(
            args.sparkbc,
            args.weights,
            source=src,
            command=cmd,
        )
        text = json.dumps(payload, indent=2) + "\n"
    elif args.stub:
        payload = emit_stub(args.sparkbc, source=src, command=cmd)
        text = json.dumps(payload, indent=2) + "\n"
    else:
        bc = load_sparkbc(args.sparkbc)
        text = format_dump(
            bc, source=src, command=cmd, label=args.label
        )
    if args.out:
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(text, encoding="utf-8")
        print("wrote %s" % out)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
