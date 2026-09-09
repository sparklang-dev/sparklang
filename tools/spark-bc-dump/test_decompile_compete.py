#!/usr/bin/env python3
"""Unit gates for richer dump + analyze + roundtrip helpers."""

from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python"))
sys.path.insert(0, str(ROOT / "tools/spark-bc-dump"))

from analyze_project import write_project
from sparklang.model_lab.bc_dump import (
    analyze_bc,
    format_dump,
    format_dump_html,
    format_dump_json,
    load_sparkbc,
)

STEP_BC = ROOT / "docs/examples/spark-train-step.sparkbc"


def test_analyze_has_symbols_xrefs_sections() -> None:
    """Structured analysis exposes symbols, xrefs, sections."""
    bc = load_sparkbc(STEP_BC)
    a = analyze_bc(bc)
    assert a["magic"] == "SPBC"
    assert len(a["symbols"]) == a["nstrings"]
    assert len(a["sections"]) >= 4
    assert a["xrefs"]["n_ops"] >= 1
    assert a["privacy"] == "local-only"
    dump = format_dump(
        bc,
        source="examples/spark_train_step.spark",
        command="(test)",
        label="unit",
    )
    assert "## Symbols (string pool)" in dump
    assert "## Xrefs" in dump
    assert "## Sections" in dump
    payload = format_dump_json(
        bc, source="s", command="c", label="j"
    )
    assert payload["sha256"] == bc["sha256"]
    html = format_dump_html(
        bc, source="s", command="c", label="h"
    )
    assert "<table>" in html
    assert bc["sha256"] in html


def test_analyze_project_writes_artifacts() -> None:
    """Analysis project folder contains dump + report."""
    with tempfile.TemporaryDirectory(prefix="spark-ap-") as td:
        meta = write_project(
            STEP_BC,
            Path(td) / "proj",
            source="examples/spark_train_step.spark",
            command="(test)",
            label="proj",
            roundtrip={"status": "skip"},
        )
        out = Path(meta["out_dir"])
        for name in (
            "dump.txt",
            "dump.json",
            "dump.html",
            "report.md",
            "roundtrip.json",
        ):
            assert (out / name).is_file(), name
        data = json.loads((out / "dump.json").read_text())
        assert data["format"] == "SPARK_BC"


def main() -> int:
    """Run compete unit gates."""
    test_analyze_has_symbols_xrefs_sections()
    test_analyze_project_writes_artifacts()
    print("ok test_decompile_compete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
