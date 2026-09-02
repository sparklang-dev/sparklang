#!/usr/bin/env python3
"""Scaffold / refresh Spark browser_mitm blueprint into spark-browser docs.

Writes out/os/browser_mitm from templates/os/browser (os generate SoT).
Does not overwrite fleshed Python MITM/CA packages in spark-browser.
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TPL = ROOT / "templates" / "os" / "browser"
OUT = ROOT / "out" / "os" / "browser_mitm"
BROWSER = ROOT.parent / "spark-browser"

# Top-level docs mirrored into spark-browser/docs/spark-*
DOC_NAMES = ("README.md", "SPEC.md", "WHY.md")


def copy_tree(src: Path, dst: Path) -> None:
    """Recursively copy template files into the emit tree."""
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst)


def ensure_browser_docs() -> None:
    """Seed spark-* docs only when missing (never clobber product edits)."""
    docs = BROWSER / "docs"
    docs.mkdir(parents=True, exist_ok=True)
    for name in DOC_NAMES:
        src = TPL / name
        if src.is_file():
            dest = docs / f"spark-{name}"
            if not dest.exists():
                shutil.copy2(src, dest)
    arch_src = TPL / "docs" / "ARCHITECTURE.md"
    arch_dst = docs / "ARCHITECTURE.md"
    if arch_src.is_file() and not arch_dst.exists():
        shutil.copy2(arch_src, arch_dst)


def main() -> int:
    """Refresh out/os/browser_mitm and ensure product docs hooks."""
    if not TPL.is_dir():
        print(f"error: missing templates at {TPL}", file=sys.stderr)
        return 1
    copy_tree(TPL, OUT)
    BROWSER.mkdir(parents=True, exist_ok=True)
    ensure_browser_docs()
    marker = BROWSER / ".spark-scaffolded"
    marker.write_text(
        "scaffolded_from=templates/os/browser\n"
        "engine=QtWebEngine/PyQt5\n"
        "product=spark-browser\n"
        "os_kind=browser\n",
        encoding="utf-8",
    )
    print(f"wrote blueprint {OUT}")
    print(f"ensured docs under {BROWSER / 'docs'}")
    print(f"product root {BROWSER}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
