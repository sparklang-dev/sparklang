#!/usr/bin/env python3
"""Example: run a .spark file from Python (dry-run default)."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python"))

from sparklang import run  # noqa: E402


def main() -> int:
    """Dry-run hello.spark and print stdout; exit with spark rc."""
    target = ROOT / "examples" / "hello.spark"
    result = run(target, cwd=ROOT)
    sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
