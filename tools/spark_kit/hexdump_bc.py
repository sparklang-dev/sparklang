#!/usr/bin/env python3
"""Hexdump a real SPARK_BC file (header + code bytes)."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT / "python") not in sys.path:
    sys.path.insert(0, str(ROOT / "python"))

from sparklang.model_lab.bc_dump import load_sparkbc


def hexdump(data: bytes, base: int = 0, width: int = 16) -> str:
    """Classic hexdump lines for bytes."""
    lines: list[str] = []
    for i in range(0, len(data), width):
        chunk = data[i : i + width]
        hex_part = " ".join("%02x" % b for b in chunk)
        ascii_part = "".join(
            chr(b) if 32 <= b < 127 else "." for b in chunk
        )
        lines.append(
            "%08x  %-47s  |%s|"
            % (base + i, hex_part, ascii_part)
        )
    return "\n".join(lines)


def dump_path(path: Path) -> str:
    """Load SPARK_BC and return hexdump with short header."""
    bc = load_sparkbc(path)
    hdr = [
        "# SparkLang SPARK_BC hexdump",
        "# path=%s" % path,
        "# sha256=%s size=%d" % (bc["sha256"], bc["size"]),
        "# never=rtx-pro-6000",
        "",
    ]
    return "\n".join(hdr) + hexdump(bc["raw"]) + "\n"


def main(argv: list[str] | None = None) -> int:
    """CLI: hexdump one .sparkbc."""
    p = argparse.ArgumentParser(prog="spark-kit-hexdump")
    p.add_argument("sparkbc", type=Path)
    p.add_argument("-o", "--out", type=Path)
    args = p.parse_args(argv)
    text = dump_path(args.sparkbc)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding="utf-8")
        print("wrote %s" % args.out)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
