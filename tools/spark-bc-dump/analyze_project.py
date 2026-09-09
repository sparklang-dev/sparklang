#!/usr/bin/env python3
"""Write a local SPARK_BC analysis project folder + report.

Outputs dump text/JSON/HTML, round-trip JSON (optional), and
``report.md``. Local-only — no upload. Does not beat Claude.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT / "python") not in sys.path:
    sys.path.insert(0, str(ROOT / "python"))

from sparklang.model_lab.bc_dump import (  # noqa: E402
    format_dump,
    format_dump_html,
    format_dump_json,
    load_sparkbc,
)


def write_project(
    sparkbc: Path,
    out_dir: Path,
    *,
    source: str = "",
    command: str = "",
    label: str = "SPARK_BC analysis",
    roundtrip: dict | None = None,
) -> dict[str, object]:
    """Create analysis project artifacts under out_dir."""
    out_dir.mkdir(parents=True, exist_ok=True)
    bc = load_sparkbc(sparkbc)
    src = source or str(sparkbc)
    cmd = command or "(already compiled)"
    text = format_dump(bc, source=src, command=cmd, label=label)
    payload = format_dump_json(
        bc, source=src, command=cmd, label=label
    )
    html = format_dump_html(
        bc, source=src, command=cmd, label=label
    )
    (out_dir / "dump.txt").write_text(text, encoding="utf-8")
    (out_dir / "dump.json").write_text(
        json.dumps(payload, indent=2) + "\n", encoding="utf-8"
    )
    (out_dir / "dump.html").write_text(html, encoding="utf-8")
    if roundtrip is not None:
        (out_dir / "roundtrip.json").write_text(
            json.dumps(roundtrip, indent=2) + "\n",
            encoding="utf-8",
        )
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
    report = "\n".join(
        [
            "# SPARK_BC analysis report",
            "",
            "- generated: %s (UTC)" % ts,
            "- path: `%s`" % sparkbc,
            "- sha256: `%s`" % bc["sha256"],
            "- size: %d bytes" % bc["size"],
            "- symbols: %d" % len(payload["symbols"]),
            "- ops: %d" % len(payload["ops"]),
            "- sections: %d" % len(payload["sections"]),
            "- privacy: local-only (no upload)",
            "",
            "## Artifacts",
            "",
            "| File | Role |",
            "|------|------|",
            "| `dump.txt` | human disasm + xrefs |",
            "| `dump.json` | structured export |",
            "| `dump.html` | local HTML report |",
            "| `roundtrip.json` | compile→dump→recompile "
            "(when run) |",
            "",
            "## Honesty",
            "",
            "Inspect / disasm of **SPARK_BC**, not ELF/PE "
            "decompile and not lossless `.spark` recovery.",
            "Does **not** beat Claude. Never 6000.",
            "",
        ]
    )
    (out_dir / "report.md").write_text(report, encoding="utf-8")
    return {
        "out_dir": str(out_dir),
        "sha256": bc["sha256"],
        "files": [
            "dump.txt",
            "dump.json",
            "dump.html",
            "report.md",
        ]
        + (["roundtrip.json"] if roundtrip is not None else []),
    }


def main(argv: list[str] | None = None) -> int:
    """CLI: sparkbc → analysis project folder."""
    p = argparse.ArgumentParser(prog="spark-bc-analyze")
    p.add_argument("sparkbc", help="path to a real .sparkbc")
    p.add_argument(
        "-o",
        "--out",
        required=True,
        help="analysis project directory",
    )
    p.add_argument("--source", default="")
    p.add_argument("--command", default="")
    p.add_argument("--label", default="SPARK_BC analysis")
    args = p.parse_args(argv)
    meta = write_project(
        Path(args.sparkbc),
        Path(args.out),
        source=args.source,
        command=args.command,
        label=args.label,
    )
    print(json.dumps(meta, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
