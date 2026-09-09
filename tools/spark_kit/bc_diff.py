#!/usr/bin/env python3
"""Diff two real SPARK_BC files by hash and decoded structure."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT / "python") not in sys.path:
    sys.path.insert(0, str(ROOT / "python"))

from sparklang.model_lab.bc_dump import decode_ops, load_sparkbc


def _summary(bc: dict) -> dict:
    ops = decode_ops(bc)
    names = [o["name"] for o in ops]
    return {
        "sha256": bc["sha256"],
        "size": bc["size"],
        "nstrs": len(bc["strings"]),
        "nconsts": len(bc["consts"]),
        "ncode": bc["ncode"],
        "ops": names,
    }


def diff_sparkbc(path_a: Path, path_b: Path) -> int:
    """Print a structural diff; return 0 if identical, 1 if different."""
    a = load_sparkbc(path_a)
    b = load_sparkbc(path_b)
    sa, sb = _summary(a), _summary(b)
    same = sa["sha256"] == sb["sha256"]
    print("a=%s sha256=%s size=%d" % (path_a, sa["sha256"][:16], sa["size"]))
    print("b=%s sha256=%s size=%d" % (path_b, sb["sha256"][:16], sb["size"]))
    if same:
        print("IDENTICAL")
        return 0
    print("DIFFER")
    for key in ("size", "nstrs", "nconsts", "ncode"):
        if sa[key] != sb[key]:
            print("  %s: %s -> %s" % (key, sa[key], sb[key]))
    if sa["ops"] != sb["ops"]:
        print("  ops_a: %s" % " ".join(sa["ops"]))
        print("  ops_b: %s" % " ".join(sb["ops"]))
    return 1


def main(argv: list[str] | None = None) -> int:
    """CLI entry for spark-bc-diff."""
    p = argparse.ArgumentParser(prog="spark-bc-diff")
    p.add_argument("a", type=Path)
    p.add_argument("b", type=Path)
    args = p.parse_args(argv)
    return diff_sparkbc(args.a, args.b)


if __name__ == "__main__":
    raise SystemExit(main())
