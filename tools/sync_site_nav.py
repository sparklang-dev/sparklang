#!/usr/bin/env python3
"""Inject shared primary nav into all website HTML pages."""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from site_primary_nav import (  # noqa: E402
    NAV_BEGIN,
    NAV_END,
    render_primary_nav_block,
    render_primary_nav_inner,
)

WEBSITE = ROOT / "website"

# Match existing primary nav + CTA (flat or already nested).
_NAV_RE = re.compile(
    r'(<nav class="site-nav"[^>]*>)\s*'
    r'(?:<!-- spark-primary-nav:begin -->\s*)?'
    r'<ul class="nav-primary">.*?</ul>\s*'
    r'<a href="[^"]*" class="nav-cta">[^<]*</a>\s*'
    r'(?:<!-- spark-primary-nav:end -->\s*)?'
    r'(</nav>)',
    re.S,
)


def iter_html() -> list[Path]:
    """All site HTML files under website/."""
    return sorted(WEBSITE.rglob("*.html"))


def replace_nav(html: str) -> tuple[str, bool]:
    """Replace primary nav block; return (html, changed)."""
    block = render_primary_nav_block(indent="            ")

    def repl(m: re.Match[str]) -> str:
        return f"{m.group(1)}\n{block}\n          {m.group(2)}"

    new, n = _NAV_RE.subn(repl, html, count=1)
    if n:
        return new, new != html
    # Marker-only rewrite if structure drifted.
    if NAV_BEGIN in html and NAV_END in html:
        pattern = re.compile(
            re.escape(NAV_BEGIN) + r".*?" + re.escape(NAV_END),
            re.S,
        )
        inner = render_primary_nav_inner(indent="            ")
        replacement = (
            f"{NAV_BEGIN}\n{inner}\n            {NAV_END}"
        )
        new2, n2 = pattern.subn(replacement, html, count=1)
        return new2, bool(n2) and new2 != html
    return html, False


def sync_all(*, check: bool = False) -> int:
    """Write or verify primary nav on every HTML page with site-nav."""
    missing = 0
    changed = 0
    skipped = 0
    for path in iter_html():
        text = path.read_text(encoding="utf-8")
        if 'class="site-nav"' not in text:
            skipped += 1
            continue
        new, did = replace_nav(text)
        if not did and 'nav-sub__label' not in text:
            print(f"NO MATCH {path.relative_to(ROOT)}")
            missing += 1
            continue
        if check:
            if text != new:
                print(f"STALE {path.relative_to(ROOT)}")
                missing += 1
            continue
        if did:
            path.write_text(new, encoding="utf-8")
            print(f"synced {path.relative_to(ROOT)}")
            changed += 1
    if check:
        if missing:
            print(f"nav sync check FAILED ({missing})")
            return 1
        print("nav sync check OK")
        return 0
    print(f"nav sync done — {changed} updated, {skipped} without site-nav")
    return 0 if missing == 0 else 1


def main() -> int:
    """CLI entry: sync or --check marketing + docs HTML nav."""
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--check",
        action="store_true",
        help="Fail if any site-nav page differs from SoT",
    )
    args = ap.parse_args()
    return sync_all(check=args.check)


if __name__ == "__main__":
    raise SystemExit(main())
