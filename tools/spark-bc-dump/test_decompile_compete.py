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
from decompile_bench import (
    NOT_PROBED,
    PARITY_TOOLS,
    _capability_matrix,
    build_scoreboard,
)
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


def _fake_rt(status: str, pct: float, n_pass: int = 1,
             n_total: int = 1) -> dict:
    """Synthetic roundtrip summary for capability-matrix checks."""
    return {
        "status": status,
        "round_trip_pct": pct,
        "n_pass": n_pass,
        "n_total": n_total,
    }


def _fake_fixture(ok: bool = True) -> dict:
    return {
        "name": "synthetic",
        "status": "ok" if ok else "fail",
        "n_symbols": 3 if ok else 0,
        "n_const_refs": 2 if ok else 0,
    }


def test_parity_badges_computed_not_declared() -> None:
    """No badge is a constant: flip the measured inputs, the cells flip."""
    fixtures = [_fake_fixture()]
    rt_pass = _fake_rt("pass", 100.0)
    rt_fail = _fake_rt("fail", 0.0, n_pass=0)
    elf_ok = {"status": "ok", "format": "elf", "section_count": 8}
    elf_skip = {"status": "skip"}
    project_ok = {"files": ["dump.txt", "report.md"]}

    m = _capability_matrix(fixtures, rt_pass, elf_ok, project_ok)
    by_cat = {row["category"]: row for row in m}
    assert by_cat["Native dump fidelity (SPARK_BC)"]["spark"] == "win"
    assert (
        by_cat["Round-trip reassemble (compile hash)"]["spark"] == "win"
    )
    assert by_cat["Symbol + xref extraction (SPARK_BC)"]["spark"] == "win"
    assert by_cat["Report export (txt/json/html project)"]["spark"] == "win"
    assert by_cat["Multi-format ELF/PE"]["spark"] == "loss"  # measured
    assert by_cat["Batch / fixtures harness"]["spark"] == "win"
    assert by_cat["Local privacy (no upload)"]["spark"] == "win"

    # Spark-only schema: no third-party tool keys anywhere.
    for row in m:
        assert set(row) == {"category", "spark", "note"}, row

    # Roundtrip failure flips the Spark badge to a measured loss.
    m2 = _capability_matrix(fixtures, rt_fail, elf_ok, project_ok)
    c2 = {row["category"]: row for row in m2}
    assert c2["Round-trip reassemble (compile hash)"]["spark"] == "loss"
    # No ELF probe → the ELF cell degrades to "not probed", never declared.
    m3 = _capability_matrix(fixtures, rt_pass, elf_skip, project_ok)
    c3 = {row["category"]: row for row in m3}
    assert c3["Multi-format ELF/PE"]["spark"] == NOT_PROBED
    # No fixtures → fidelity/extraction/batch cells are measured losses.
    m4 = _capability_matrix([], _fake_rt("fail", 0.0, 0, 0), elf_skip, {})
    c4 = {row["category"]: row for row in m4}
    assert c4["Native dump fidelity (SPARK_BC)"]["spark"] == "loss"
    assert c4["Symbol + xref extraction (SPARK_BC)"]["spark"] == "loss"
    assert c4["Batch / fixtures harness"]["spark"] == "loss"


def test_scoreboard_parity_cells_are_probe_derived() -> None:
    """Live scoreboard: every cell measured; schema carries no tool columns."""
    sb = build_scoreboard()
    matrix = sb["parity"]
    for row in matrix:
        for tool in PARITY_TOOLS:
            assert tool in row, (row["category"], tool)
            cell = row[tool]
            assert cell in {"win", "tie", "loss", "na", NOT_PROBED}
    # Spark's own badges are computed from measured inputs that exist here.
    by_cat = {row["category"]: row for row in matrix}
    assert by_cat["Native dump fidelity (SPARK_BC)"]["spark"] == "win"
    assert (
        by_cat["Round-trip reassemble (compile hash)"]["spark"] == "win"
    )
    counts = sb["summary_counts"]
    assert set(counts) == {"spark"}
    # Methodology field renamed from the old schema key.
    assert "methodology" in sb
    assert "honesty" not in sb
    # No third-party probe list is published.
    assert "external_tools" not in sb


def main() -> int:
    """Run compete unit gates."""
    test_analyze_has_symbols_xrefs_sections()
    test_analyze_project_writes_artifacts()
    test_parity_badges_computed_not_declared()
    test_scoreboard_parity_cells_are_probe_derived()
    print("ok test_decompile_compete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
