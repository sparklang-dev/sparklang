#!/usr/bin/env python3
"""Shadow copy, shadow-build dir, and hash verify for Spark artifacts.

Never 6000. Does not claim beat Claude.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def _root() -> Path:
    env = os.environ.get("SPARK_ROOT")
    if env:
        return Path(env).resolve()
    return Path(__file__).resolve().parents[2]


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            chunk = f.read(1 << 20)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def shadow_root() -> Path:
    """Return build/shadow path (override SPARK_SHADOW_ROOT)."""
    override = os.environ.get("SPARK_SHADOW_ROOT")
    if override:
        return Path(override).resolve()
    return _root() / "build" / "shadow"


def cmd_copy(path: Path, dest_dir: Path | None = None) -> Path:
    """Copy path to a timestamped shadow; return shadow path."""
    src = path.resolve()
    if not src.is_file():
        raise FileNotFoundError("missing file: %s" % src)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out_dir = dest_dir or (src.parent / ".shadow")
    out_dir.mkdir(parents=True, exist_ok=True)
    shadow = out_dir / ("%s.%s" % (src.name, stamp))
    shutil.copy2(src, shadow)
    print("shadow_copy src=%s" % src)
    print("shadow_copy dst=%s" % shadow)
    print("sha256=%s" % _sha256(shadow))
    return shadow


def cmd_build_dir(create: bool = True) -> Path:
    """Ensure and print the shadow build directory."""
    d = shadow_root()
    if create:
        d.mkdir(parents=True, exist_ok=True)
        (d / ".gitkeep").touch(exist_ok=True)
    print("SPARK_SHADOW_ROOT=%s" % d)
    return d


def cmd_verify(orig: Path, shadow: Path) -> int:
    """Compare SHA-256 of original and shadow; 0 match, 1 miss."""
    if not orig.is_file() or not shadow.is_file():
        print("FAIL missing file")
        return 1
    a, b = _sha256(orig), _sha256(shadow)
    print("orig=%s sha256=%s" % (orig, a))
    print("shadow=%s sha256=%s" % (shadow, b))
    if a == b:
        print("VERIFY_OK")
        return 0
    print("VERIFY_FAIL")
    return 1


def cmd_verify_recompile(src: Path, bc: Path) -> int:
    """Recompile .spark and compare hash to existing .sparkbc."""
    root = _root()
    boot = root / "spark-bootstrap"
    if not boot.is_file():
        boot = root / "bin" / "spark-bootstrap"
    if not boot.is_file():
        print("FAIL missing spark-bootstrap")
        return 1
    shadow_d = shadow_root()
    shadow_d.mkdir(parents=True, exist_ok=True)
    tmp = shadow_d / ("recompile-%s.sparkbc" % src.stem)
    proc = subprocess.run(
        [str(boot), "--compile", str(src), "-o", str(tmp)],
        cwd=str(root),
        check=False,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        print("FAIL compile: %s" % (proc.stderr or proc.stdout))
        return 1
    return cmd_verify(bc, tmp)


def main(argv: list[str] | None = None) -> int:
    """CLI dispatcher for spark-shadow."""
    p = argparse.ArgumentParser(prog="spark-shadow")
    sub = p.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("copy", help="timestamped shadow copy")
    c.add_argument("path", type=Path)
    c.add_argument("--dir", type=Path, default=None)

    b = sub.add_parser("build-dir", help="print/create build/shadow")
    b.add_argument(
        "--no-create",
        action="store_true",
        help="do not mkdir",
    )

    v = sub.add_parser("verify", help="compare SHA-256")
    v.add_argument("orig", type=Path)
    v.add_argument("shadow", type=Path)

    r = sub.add_parser(
        "verify-recompile",
        help="recompile .spark and compare to .sparkbc",
    )
    r.add_argument("src", type=Path)
    r.add_argument("sparkbc", type=Path)

    args = p.parse_args(argv)
    if args.cmd == "copy":
        cmd_copy(args.path, args.dir)
        return 0
    if args.cmd == "build-dir":
        cmd_build_dir(create=not args.no_create)
        return 0
    if args.cmd == "verify":
        return cmd_verify(args.orig, args.shadow)
    if args.cmd == "verify-recompile":
        return cmd_verify_recompile(args.src, args.sparkbc)
    p.error("unknown command")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
