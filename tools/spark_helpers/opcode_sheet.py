#!/usr/bin/env python3
"""Emit SPARK_BC opcode sheet from real OP_NAME / OP_ARITY tables."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python"))

from sparklang.model_lab.bc_dump import OP_ARITY, OP_NAME  # noqa: E402


def main() -> int:
    """Print opcode sheet (hex, name, arity) to stdout."""
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
    sys.stdout.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
