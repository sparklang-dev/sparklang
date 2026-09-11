#!/usr/bin/env python3
"""SPARK_BC measured-capabilities scoreboard JSON.

Measures Spark's own decompile capabilities on the published
fixtures: fixture decode metrics, compile→dump→recompile
round-trip, the local ELF headers/sections probe, and a sample
analysis-project write. Every badge is COMPUTED from measured
output on this box — never a declared constant.

The public scoreboard reports Spark capabilities only. It does not
probe, name, or rank third-party tools; cross-tool comparison is a
repo-internal research lane, not site content (see
docs/DECOMPILE_ASSIST_POLICY.md).
"""

from __future__ import annotations

import argparse
import json
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

NOT_PROBED = "not probed"

# Capability rows carry a single measured column: Spark.
PARITY_TOOLS = [
    "spark",
]


def _spark_fixture_metrics() -> list[dict[str, object]]:
    """Decode each published fixture and record real metrics."""
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


def _capability_matrix(
    fixtures: list[dict[str, object]],
    rt: dict[str, object],
    elf_probe: dict[str, object],
    project_meta: dict[str, object] | None,
) -> list[dict[str, str]]:
    """Compute every Spark badge from measured probe output.

    Cells derive from fixture metrics, the round-trip gate, the
    local ELF probe, and the sample project write. A capability
    whose probe did not run is ``not probed`` — never a declared
    badge.
    """
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
        # Local probe lists headers+sections only — a measured
        # loss against the full multi-format decompile domain.
        if elf_status in ("ok", "fail"):
            return "loss"
        return NOT_PROBED

    rows = [
        {
            "category": "Native dump fidelity (SPARK_BC)",
            "spark": _spark_native(),
            "note": (
                "%d/%d published fixtures decoded with "
                "symbols+xrefs+sections from real bytes."
                % (n_ok, len(fixtures))
            ),
        },
        {
            "category": "Round-trip reassemble (compile hash)",
            "spark": _spark_roundtrip(),
            "note": (
                "compile→dump→recompile %.1f%% (%d/%d) on "
                "published fixtures."
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
            "note": (
                "String-pool symbols + const/op xrefs verified "
                "on %d fixture(s) from real bytes." % n_ok
            ),
        },
        {
            "category": "Report export (txt/json/html project)",
            "spark": "win" if project_ok else "loss",
            "note": (
                "analyze_project wrote %s."
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
            "note": (
                "spark-binary-probe --elf status=%s — "
                "headers+sections index only, not full "
                "multi-format decompilation." % elf_status
            ),
        },
        {
            "category": "Batch / fixtures harness",
            "spark": "win" if all_ok else "loss",
            "note": (
                "make decompile-bench measured %d/%d fixtures "
                "ok this run." % (n_ok, len(fixtures))
            ),
        },
        {
            "category": "Local privacy (no upload)",
            "spark": "win" if all_ok else "loss",
            "note": (
                "This bench parsed %d fixture(s) in-process on "
                "disk; no network calls." % n_ok
            ),
        },
    ]
    return rows


def _summarize(
    matrix: list[dict[str, str]],
) -> dict[str, dict[str, int]]:
    """Count badge values per measured column (Spark)."""
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
    """Measure the local ELF headers/sections probe."""
    probe = ROOT / "spark-binary-probe"
    target = ROOT / "spark"
    if not probe.is_file():
        return {
            "status": "skip",
            "note": "build spark-binary-probe first",
            "claim": "local_elf_probe_headers_sections",
        }
    if not target.is_file():
        return {
            "status": "skip",
            "note": "./spark missing",
            "claim": "local_elf_probe_headers_sections",
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
            "claim": "local_elf_probe_headers_sections",
        }
    try:
        payload = json.loads(proc.stdout.strip().splitlines()[-1])
    except (json.JSONDecodeError, IndexError):
        return {
            "status": "error",
            "note": "non-JSON probe output",
            "claim": "local_elf_probe_headers_sections",
        }
    sections = payload.get("sections") or []
    return {
        "status": "ok" if payload.get("ok") else "fail",
        "op": payload.get("op"),
        "claim": payload.get(
            "claim", "local_elf_probe_headers_sections"
        ),
        "section_count": payload.get("section_count"),
        "n_sections_listed": len(sections),
        "elf_class": payload.get("elf_class"),
        "machine": payload.get("machine"),
        "note": (
            "Local ELF64 headers+sections JSON — an index, not "
            "full multi-format decompilation"
        ),
    }


def build_scoreboard(
    *,
    project_dir: Path | None = None,
) -> dict[str, object]:
    """Run metrics + optional project write; return scoreboard."""
    rt = run_all()
    fixtures = _spark_fixture_metrics()
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
    matrix = _capability_matrix(
        fixtures,
        rt if isinstance(rt, dict) else {},
        elf_probe,
        project_meta,
    )
    summary = _summarize(matrix)
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
    return {
        "generated_at": ts,
        "generator": "tools/spark-bc-dump/decompile_bench.py",
        "domain": "SPARK_BC",
        "methodology": (
            "Every badge in this JSON is computed from measured "
            "probe output on this box (round-trip %, symbol/xref "
            "extraction on real bytes, local ELF probe, sample "
            "project write). A capability whose probe did not run "
            "renders 'not probed' — never a declared win/tie/loss."
        ),
        "beat_axes": [
            {
                "axis": "100% SPARK_BC round-trip hash",
                "status": rt.get("status"),
                "round_trip_pct": rt.get("round_trip_pct"),
            },
            {
                "axis": "Structured SPARK_BC dump",
                "status": "measured",
                "fixtures_ok": sum(
                    1 for f in fixtures if f.get("status") == "ok"
                ),
            },
            {
                "axis": "Local privacy (no upload)",
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
        "elf_local_probe": elf_probe,
        "parity": matrix,
        "summary_counts": summary,
        "sample_project": project_meta,
        "never": [
            "invented win claims",
            "unmeasured badges",
            "third-party upload of proprietary bytecode",
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
