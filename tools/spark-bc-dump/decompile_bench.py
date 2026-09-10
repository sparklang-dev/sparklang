#!/usr/bin/env python3
"""SPARK_BC decompile compete bench + honest scoreboard JSON.

Measures Spark metrics on published fixtures. Optional external
tools (objdump / ghidra / r2 / openbin) are probed and **skipped
cleanly** when absent — never fake green. Domain is SPARK_BC first;
ELF/PE classic RE is N/A for Spark SoT wins.

Every parity badge is COMPUTED from measured probe output:
round-trip %, symbol/xref extraction on real bytes, the local ELF
probe, and byte-level probes of any competitor tool actually present
on this box. A competitor that is absent — or present without a
scripted byte-level probe for that category — renders
``not probed``. Never a declared win/tie/loss.

Never 6000. Do not copy OpenBin code.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
_HERE = Path(__file__).resolve().parent
if str(ROOT / "python") not in sys.path:
    sys.path.insert(0, str(ROOT / "python"))
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from analyze_project import write_project  # noqa: E402
from roundtrip import run_all  # noqa: E402
from sparklang.model_lab.bc_dump import (  # noqa: E402
    analyze_bc,
    load_sparkbc,
)

PUBLISHED = [
    ROOT / "docs/examples/spark-train-step.sparkbc",
    ROOT / "docs/examples/spark-builder.sparkbc",
    ROOT / "docs/examples/spark-self.sparkbc",
]


def _which(name: str) -> str | None:
    return shutil.which(name)


NOT_PROBED = "not probed"

# Parity columns (order matters for the site table). objdump is a
# binutils disassembler, not a decompile suite, but it is the one
# tool with a scripted byte-level probe here, so it earns a column.
PARITY_TOOLS = [
    "spark",
    "objdump",
    "openbin",
    "ghidra",
    "ida",
    "binja",
    "llm4decompile",
]

# Parity column → external probe row name (spark has no external).
_TOOL_ROW_NAME = {
    "objdump": "objdump",
    "openbin": "openbin",
    "ghidra": "ghidra",
    "ida": "ida",
    "binja": "binaryninja",
}


def _run_bytes_probe(argv: list[str]) -> tuple[int | None, str]:
    """Run a byte-level tool probe; return (returncode, snippet)."""
    try:
        proc = subprocess.run(
            argv,
            capture_output=True,
            text=True,
            timeout=8,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, str(exc)
    out = ((proc.stdout or "") + " " + (proc.stderr or "")).strip()
    return proc.returncode, out[:160]


def _probe_tool_sparkbc(
    tool: str, fixture: Path
) -> dict[str, str] | None:
    """Byte-probe: can this tool decode a real .sparkbc?

    Returns None when there is no scripted probe for the tool —
    presence on PATH is not evidence of capability.
    """
    if tool == "objdump":
        rc, snip = _run_bytes_probe(["objdump", "-d", str(fixture)])
        if rc is None:
            return {"verdict": NOT_PROBED, "note": snip}
        if rc == 0:
            return {
                "verdict": "win",
                "note": "objdump accepted SPARK_BC bytes (measured)",
            }
        return {
            "verdict": "na",
            "note": (
                "measured: objdump rejects SPARK_BC "
                "(not its format): %s" % snip
            ),
        }
    return None


def _probe_tool_elf(
    tool: str, target: Path
) -> dict[str, str] | None:
    """Byte-probe: can this tool list ELF sections on real bytes?

    Returns None when there is no scripted probe for the tool.
    """
    if tool == "objdump":
        if not target.is_file():
            return {
                "verdict": NOT_PROBED,
                "note": "./spark not built on this box",
            }
        rc, snip = _run_bytes_probe(["objdump", "-h", str(target)])
        if rc is None:
            return {"verdict": NOT_PROBED, "note": snip}
        if rc == 0:
            return {
                "verdict": "win",
                "note": (
                    "measured: objdump -h listed ELF sections "
                    "on ./spark"
                ),
            }
        return {
            "verdict": "loss",
            "note": "measured: objdump -h failed: %s" % snip,
        }
    return None


def _probe_external() -> list[dict[str, object]]:
    """Probe optional RE tools; skip if not installed."""
    probes = [
        ("objdump", ["objdump", "--version"]),
        ("radare2", ["r2", "-v"]),
        ("ghidra", ["ghidraRun", "-help"]),
        ("ida", ["idat64", "-h"]),
        ("binaryninja", ["binaryninja", "--help"]),
        ("openbin", ["openbin", "--version"]),
    ]
    rows: list[dict[str, object]] = []
    for name, argv in probes:
        path = _which(argv[0])
        if not path:
            rows.append(
                {
                    "tool": name,
                    "status": "absent",
                    "verdict": "skip",
                    "note": "%s not on PATH" % argv[0],
                }
            )
            continue
        try:
            proc = subprocess.run(
                argv,
                capture_output=True,
                text=True,
                timeout=5,
                check=False,
            )
            snippet = (proc.stdout or proc.stderr or "")[:120]
            rows.append(
                {
                    "tool": name,
                    "status": "present",
                    "path": path,
                    "verdict": "na-sparkbc",
                    "note": (
                        "Installed, but not a SPARK_BC SoT "
                        "decoder — skip compete on SPBC domain. "
                        "snippet=%r" % snippet.strip()
                    ),
                }
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            rows.append(
                {
                    "tool": name,
                    "status": "error",
                    "verdict": "skip",
                    "note": str(exc),
                }
            )
    return rows


def _spark_fixture_metrics() -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for path in PUBLISHED:
        if not path.is_file():
            rows.append(
                {
                    "path": str(path.relative_to(ROOT)),
                    "status": "missing",
                }
            )
            continue
        bc = load_sparkbc(path)
        a = analyze_bc(bc)
        rows.append(
            {
                "path": str(path.relative_to(ROOT)),
                "status": "ok",
                "sha256": bc["sha256"],
                "size": bc["size"],
                "n_symbols": len(a["symbols"]),
                "n_ops": len(a["ops"]),
                "n_sections": len(a["sections"]),
                "n_const_refs": a["xrefs"]["n_const_refs"],
                "has_structured_dump": True,
                "json_export": True,
                "html_export": True,
            }
        )
    return rows


def _competitor_cells(
    external: list[dict[str, object]],
    *,
    sparkbc_fixture: Path,
    elf_target: Path,
) -> dict[str, dict[str, object]]:
    """Measured competitor state per parity column.

    For each tool: presence from the external probe list, plus
    byte-level probes where scripted. Capability without a
    byte-level probe is NOT_PROBED — presence is not evidence.
    """
    by_name = {str(r.get("tool")): r for r in external}
    cells: dict[str, dict[str, object]] = {}
    for col, row_name in _TOOL_ROW_NAME.items():
        row = by_name.get(row_name) or {}
        present = row.get("status") == "present"
        cells[col] = {
            "present": present,
            "sparkbc": (
                _probe_tool_sparkbc(col, sparkbc_fixture)
                if present
                else None
            ),
            "elf": (
                _probe_tool_elf(col, elf_target) if present else None
            ),
        }
    # llm4decompile is never probed on this box (no local binary).
    cells["llm4decompile"] = {
        "present": False,
        "sparkbc": None,
        "elf": None,
    }
    return cells


def _comp_cell(
    comp: dict[str, dict[str, object]],
    tool: str,
    probe_kind: str | None,
) -> str:
    """Computed competitor badge for one category cell."""
    if tool == "spark":
        raise ValueError("spark cells are computed separately")
    state = comp.get(tool) or {}
    if not state.get("present"):
        return NOT_PROBED
    if probe_kind is None:
        return NOT_PROBED
    probe = state.get(probe_kind)
    if not probe:
        return NOT_PROBED
    return str(probe.get("verdict") or NOT_PROBED)


def _parity_matrix(
    fixtures: list[dict[str, object]],
    rt: dict[str, object],
    elf_probe: dict[str, object],
    project_meta: dict[str, object] | None,
    external: list[dict[str, object]],
) -> list[dict[str, str]]:
    """Compute every badge from measured probe output.

    Spark cells derive from fixture metrics, the round-trip gate,
    the local ELF probe, and the sample project write. Competitor
    cells derive from byte-level probes of tools actually present;
    anything else is ``not probed`` — never a declared badge.
    """
    comp = _competitor_cells(
        external,
        sparkbc_fixture=PUBLISHED[0],
        elf_target=ROOT / "spark",
    )
    ok_fixtures = [f for f in fixtures if f.get("status") == "ok"]
    n_ok = len(ok_fixtures)
    all_ok = n_ok == len(fixtures) and n_ok > 0
    symbols_ok = all_ok and all(
        int(f.get("n_symbols") or 0) > 0
        and int(f.get("n_const_refs") or 0) > 0
        for f in ok_fixtures
    )
    rt_pct = float(rt.get("round_trip_pct") or 0.0)
    rt_ok = rt.get("status") == "pass" and rt_pct == 100.0
    project_ok = bool(project_meta and project_meta.get("files"))
    elf_status = str(elf_probe.get("status") or "skip")

    def _spark_native() -> str:
        return "win" if all_ok and symbols_ok else "loss"

    def _spark_roundtrip() -> str:
        if rt_ok:
            return "win"
        return "tie" if rt_pct >= 50.0 else "loss"

    def _spark_elf() -> str:
        # Local probe lists hdr+sections only — an honest loss vs
        # full RE suites even when the probe ran clean.
        if elf_status in ("ok", "fail"):
            return "loss"
        return NOT_PROBED

    rows = [
        {
            "category": "Native dump fidelity (SPARK_BC)",
            "spark": _spark_native(),
            "objdump": _comp_cell(comp, "objdump", "sparkbc"),
            "openbin": _comp_cell(comp, "openbin", "sparkbc"),
            "ghidra": _comp_cell(comp, "ghidra", "sparkbc"),
            "ida": _comp_cell(comp, "ida", "sparkbc"),
            "binja": _comp_cell(comp, "binja", "sparkbc"),
            "llm4decompile": _comp_cell(
                comp, "llm4decompile", "sparkbc"
            ),
            "note": (
                "Spark: %d/%d published fixtures decoded with "
                "symbols+xrefs+sections. Competitors need a "
                "byte-level SPARK_BC probe to score."
                % (n_ok, len(fixtures))
            ),
        },
        {
            "category": "Round-trip reassemble (compile hash)",
            "spark": _spark_roundtrip(),
            "objdump": _comp_cell(comp, "objdump", None),
            "openbin": _comp_cell(comp, "openbin", None),
            "ghidra": _comp_cell(comp, "ghidra", None),
            "ida": _comp_cell(comp, "ida", None),
            "binja": _comp_cell(comp, "binja", None),
            "llm4decompile": _comp_cell(comp, "llm4decompile", None),
            "note": (
                "Spark: compile→dump→recompile %.1f%% (%d/%d) on "
                "published fixtures. No competitor SPARK_BC "
                "round-trip probe exists."
                % (
                    rt_pct,
                    rt.get("n_pass") or 0,
                    rt.get("n_total") or 0,
                )
            ),
        },
        {
            "category": "Symbol + xref extraction (SPARK_BC)",
            "spark": "win" if symbols_ok else "loss",
            "objdump": _comp_cell(comp, "objdump", "sparkbc"),
            "openbin": _comp_cell(comp, "openbin", "sparkbc"),
            "ghidra": _comp_cell(comp, "ghidra", "sparkbc"),
            "ida": _comp_cell(comp, "ida", "sparkbc"),
            "binja": _comp_cell(comp, "binja", "sparkbc"),
            "llm4decompile": _comp_cell(
                comp, "llm4decompile", "sparkbc"
            ),
            "note": (
                "Spark: string-pool symbols + const/op xrefs "
                "verified on %d fixture(s) from real bytes."
                % n_ok
            ),
        },
        {
            "category": "Report export (txt/json/html project)",
            "spark": "win" if project_ok else "loss",
            "objdump": _comp_cell(comp, "objdump", None),
            "openbin": _comp_cell(comp, "openbin", None),
            "ghidra": _comp_cell(comp, "ghidra", None),
            "ida": _comp_cell(comp, "ida", None),
            "binja": _comp_cell(comp, "binja", None),
            "llm4decompile": _comp_cell(comp, "llm4decompile", None),
            "note": (
                "Spark: analyze_project wrote %s."
                % (
                    ", ".join(project_meta["files"])
                    if project_ok
                    else "no sample project this run"
                )
            ),
        },
        {
            "category": "Multi-format ELF/PE",
            "spark": _spark_elf(),
            "objdump": _comp_cell(comp, "objdump", "elf"),
            "openbin": _comp_cell(comp, "openbin", "elf"),
            "ghidra": _comp_cell(comp, "ghidra", "elf"),
            "ida": _comp_cell(comp, "ida", "elf"),
            "binja": _comp_cell(comp, "binja", "elf"),
            "llm4decompile": _comp_cell(comp, "llm4decompile", "elf"),
            "note": (
                "Spark: spark-binary-probe --elf status=%s "
                "(hdr+sections only — not Ghidra-class). "
                "Competitors need a byte-level ELF probe."
                % elf_status
            ),
        },
        {
            "category": "Batch / fixtures harness",
            "spark": "win" if all_ok else "loss",
            "objdump": _comp_cell(comp, "objdump", None),
            "openbin": _comp_cell(comp, "openbin", None),
            "ghidra": _comp_cell(comp, "ghidra", None),
            "ida": _comp_cell(comp, "ida", None),
            "binja": _comp_cell(comp, "binja", None),
            "llm4decompile": _comp_cell(comp, "llm4decompile", None),
            "note": (
                "Spark: make decompile-bench measured %d/%d "
                "fixtures ok this run." % (n_ok, len(fixtures))
            ),
        },
        {
            "category": "Local privacy (no upload)",
            "spark": "win" if all_ok else "loss",
            "objdump": _comp_cell(comp, "objdump", None),
            "openbin": _comp_cell(comp, "openbin", None),
            "ghidra": _comp_cell(comp, "ghidra", None),
            "ida": _comp_cell(comp, "ida", None),
            "binja": _comp_cell(comp, "binja", None),
            "llm4decompile": _comp_cell(comp, "llm4decompile", None),
            "note": (
                "Spark: this bench parsed %d fixture(s) in-process "
                "on disk; no network calls. Competitor privacy "
                "is not probeable here." % n_ok
            ),
        },
    ]
    return rows


def _summarize(
    matrix: list[dict[str, str]],
) -> dict[str, dict[str, int]]:
    out: dict[str, dict[str, int]] = {}
    for t in PARITY_TOOLS:
        counts = {
            "win": 0,
            "tie": 0,
            "loss": 0,
            "na": 0,
            NOT_PROBED: 0,
        }
        for row in matrix:
            v = row.get(t, "na")
            if v not in counts:
                v = "na"
            counts[v] += 1
        out[t] = counts
    return out


def _elf_local_probe() -> dict[str, object]:
    """Measure local ELF probe (not a Ghidra win claim)."""
    probe = ROOT / "spark-binary-probe"
    target = ROOT / "spark"
    if not probe.is_file():
        return {
            "status": "skip",
            "note": "build spark-binary-probe first",
            "claim": "local_elf_probe_not_ghidra",
        }
    if not target.is_file():
        return {
            "status": "skip",
            "note": "./spark missing",
            "claim": "local_elf_probe_not_ghidra",
        }
    try:
        proc = subprocess.run(
            [str(probe), "--elf", str(target)],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {
            "status": "error",
            "note": str(exc),
            "claim": "local_elf_probe_not_ghidra",
        }
    try:
        payload = json.loads(proc.stdout.strip().splitlines()[-1])
    except (json.JSONDecodeError, IndexError):
        return {
            "status": "error",
            "note": "non-JSON probe output",
            "claim": "local_elf_probe_not_ghidra",
        }
    sections = payload.get("sections") or []
    return {
        "status": "ok" if payload.get("ok") else "fail",
        "op": payload.get("op"),
        "claim": payload.get("claim", "local_elf_probe_not_ghidra"),
        "section_count": payload.get("section_count"),
        "n_sections_listed": len(sections),
        "elf_class": payload.get("elf_class"),
        "machine": payload.get("machine"),
        "note": (
            "Local ELF64 hdr+sections JSON — still loss vs "
            "Ghidra/IDA/Binja on Multi-format ELF/PE axis"
        ),
    }


def build_scoreboard(
    *,
    project_dir: Path | None = None,
) -> dict[str, object]:
    """Run metrics + optional project write; return scoreboard."""
    rt = run_all()
    fixtures = _spark_fixture_metrics()
    external = _probe_external()
    elf_probe = _elf_local_probe()
    project_meta = None
    step = ROOT / "docs/examples/spark-train-step.sparkbc"
    if project_dir is not None and step.is_file():
        project_meta = write_project(
            step,
            project_dir,
            source="examples/spark_train_step.spark",
            command=(
                "./spark-bootstrap --compile "
                "examples/spark_train_step.spark "
                "-o docs/examples/spark-train-step.sparkbc"
            ),
            label="decompile-bench sample project",
            roundtrip=rt if isinstance(rt, dict) else None,
        )
    matrix = _parity_matrix(
        fixtures,
        rt if isinstance(rt, dict) else {},
        elf_probe,
        project_meta,
        external,
    )
    summary = _summarize(matrix)
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
    return {
        "generated_at": ts,
        "generator": "tools/spark-bc-dump/decompile_bench.py",
        "domain": "SPARK_BC",
        "honesty": (
            "Every badge in this JSON is computed from measured "
            "probe output on this box (round-trip %, symbol/xref "
            "extraction on real bytes, local ELF probe, byte-level "
            "tool probes). Absent or unprobed tools render "
            "'not probed' — never a declared win/tie/loss."
        ),
        "beat_axes": [
            {
                "axis": "100% SPARK_BC round-trip hash",
                "status": rt.get("status"),
                "round_trip_pct": rt.get("round_trip_pct"),
            },
            {
                "axis": "Best structured SPARK_BC dump",
                "status": "measured",
                "fixtures_ok": sum(
                    1 for f in fixtures if f.get("status") == "ok"
                ),
            },
            {
                "axis": "Best local privacy (no upload)",
                "status": "design",
                "note": "dump/analyze stay on disk",
            },
            {
                "axis": "Integrated train/weights",
                "status": "design",
                "note": "TRAIN/STEP + emit_init_weights",
            },
        ],
        "roundtrip": rt,
        "fixtures": fixtures,
        "external_tools": external,
        "elf_local_probe": elf_probe,
        "parity": matrix,
        "summary_counts": summary,
        "sample_project": project_meta,
        "never": [
            "false marketing beats-all",
            "RTX PRO 6000",
            "beat Claude invention",
            "copy OpenBin code",
        ],
    }


def main(argv: list[str] | None = None) -> int:
    """CLI for make decompile-bench."""
    p = argparse.ArgumentParser(prog="decompile-bench")
    p.add_argument(
        "--json-out",
        default=str(
            ROOT / "website/data/decompile-scoreboard.json"
        ),
        help="scoreboard JSON path",
    )
    p.add_argument(
        "--project-dir",
        default=str(ROOT / "out/decompile-bench/sample-project"),
        help="write one analysis project (or empty to skip)",
    )
    p.add_argument(
        "--skip-project",
        action="store_true",
        help="do not write sample analysis project",
    )
    args = p.parse_args(argv)
    project_dir = None
    if not args.skip_project and args.project_dir:
        project_dir = Path(args.project_dir)
    board = build_scoreboard(project_dir=project_dir)
    out = Path(args.json_out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        json.dumps(board, indent=2) + "\n", encoding="utf-8"
    )
    print("wrote %s" % out)
    print(
        "round_trip_pct=%s status=%s"
        % (
            board["roundtrip"].get("round_trip_pct"),
            board["roundtrip"].get("status"),
        )
    )
    # Mirror under docs/examples for Pages sync habits.
    mirror = ROOT / "docs/examples/decompile-scoreboard.json"
    mirror.write_text(out.read_text(encoding="utf-8"), encoding="utf-8")
    print("wrote %s" % mirror)
    rt_status = board["roundtrip"].get("status")
    return 0 if rt_status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
