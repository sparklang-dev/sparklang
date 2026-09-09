#!/usr/bin/env python3
"""Emit SPARK_BC opcode sheet from real OP_NAME / OP_ARITY tables."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT / "python") not in sys.path:
    sys.path.insert(0, str(ROOT / "python"))

from sparklang.model_lab.bc_dump import OP_ARITY, OP_NAME


def sheet_text() -> str:
    """Markdown opcode cheat-sheet from live tables."""
    lines = [
        "# SparkLang SPARK_BC opcode sheet",
        "# Generated from sparklang.model_lab.bc_dump (not invented).",
        "# Never 6000. Does not claim beat Claude.",
        "",
        "| hex | name | arity |",
        "| --- | ---- | ----- |",
    ]
    for op in sorted(OP_NAME):
        lines.append(
            "| 0x%02x | %s | %d |"
            % (op, OP_NAME[op], OP_ARITY[op])
        )
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    """Print or write the opcode sheet."""
    p = argparse.ArgumentParser(prog="spark-kit-opcode-sheet")
    p.add_argument("-o", "--out", type=Path)
    args = p.parse_args(argv)
    text = sheet_text()
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding="utf-8")
        print("wrote %s" % args.out)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
