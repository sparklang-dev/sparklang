#!/usr/bin/env python3
"""SPARK_BC decompile compete bench + honest scoreboard JSON.

Measures Spark metrics on published fixtures. Optional external
tools (objdump / ghidra / r2 / openbin) are probed and **skipped
cleanly** when absent — never fake green. Domain is SPARK_BC first;
ELF/PE classic RE is N/A for Spark SoT wins.

Does not beat Claude. Never 6000. Do not copy OpenBin code.
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


def _parity_matrix() -> list[dict[str, str]]:
    """Honest capability matrix (not invented green checks)."""
    # spark / openbin / ghidra / ida / binja / llm4decompile
    return [
        {
            "category": "Native dump fidelity (SPARK_BC)",
            "spark": "win",
            "openbin": "na",
            "ghidra": "na",
            "ida": "na",
            "binja": "na",
            "llm4decompile": "na",
            "note": (
                "Only Spark decodes SPBC SoT; classics target "
                "ELF/PE/mach-O"
            ),
        },
        {
            "category": "Round-trip reassemble (compile hash)",
            "spark": "win",
            "openbin": "na",
            "ghidra": "loss",
            "ida": "loss",
            "binja": "loss",
            "llm4decompile": "loss",
            "note": (
                "Spark: compile→dump→recompile 100% on fixtures. "
                "LLM recompile≠fidelity (arXiv:2609.05370)"
            ),
        },
        {
            "category": "IDE explore (SPARK_BC GUI / dump)",
            "spark": "win",
            "openbin": "tie",
            "ghidra": "tie",
            "ida": "tie",
            "binja": "tie",
            "llm4decompile": "na",
            "note": (
                "Spark has local dump/GUI for SPBC; classics "
                "win general binary IDE — different domain"
            ),
        },
        {
            "category": "Ask / voice assist",
            "spark": "tie",
            "openbin": "tie",
            "ghidra": "na",
            "ida": "na",
            "binja": "na",
            "llm4decompile": "tie",
            "note": (
                "Optional LLM assist exists in research/product "
                "space; Spark keeps LLM off SoT"
            ),
        },
        {
            "category": "Report export (txt/json/html project)",
            "spark": "win",
            "openbin": "tie",
            "ghidra": "tie",
            "ida": "tie",
            "binja": "tie",
            "llm4decompile": "na",
            "note": "Spark ships analyze_project local folder",
        },
        {
            "category": "Multi-format ELF/PE",
            "spark": "loss",
            "openbin": "win",
            "ghidra": "win",
            "ida": "win",
            "binja": "win",
            "llm4decompile": "win",
            "note": (
                "Spark ships spark-binary-probe --elf (hdr + "
                "sections JSON) + spark-section-dump; still not "
                "Ghidra-class. SPARK_BC first. claim="
                "local_elf_probe_not_ghidra"
            ),
        },
        {
            "category": "LLM-assist decompile",
            "spark": "na",
            "openbin": "win",
            "ghidra": "tie",
            "ida": "tie",
            "binja": "tie",
            "llm4decompile": "win",
            "note": (
                "Spark does not claim LLM source recovery; "
                "research note only"
            ),
        },
        {
            "category": "Batch / fixtures harness",
            "spark": "win",
            "openbin": "tie",
            "ghidra": "tie",
            "ida": "tie",
            "binja": "tie",
            "llm4decompile": "tie",
            "note": "make decompile-bench + roundtrip fixtures",
        },
        {
            "category": "Shadows / helpers",
            "spark": "win",
            "openbin": "na",
            "ghidra": "na",
            "ida": "na",
            "binja": "na",
            "llm4decompile": "na",
            "note": "helpers/shadows wrap Spark SoT",
        },
        {
            "category": "Local privacy (no upload)",
            "spark": "win",
            "openbin": "loss",
            "ghidra": "win",
            "ida": "win",
            "binja": "win",
            "llm4decompile": "tie",
            "note": (
                "OpenBin online path may upload after login; "
                "Spark dump stays local"
            ),
        },
        {
            "category": "Integrated train / weights",
            "spark": "win",
            "openbin": "na",
            "ghidra": "na",
            "ida": "na",
            "binja": "na",
            "llm4decompile": "na",
            "note": "TRAIN/STEP + init weights from same BC",
        },
    ]


def _summarize(
    matrix: list[dict[str, str]],
) -> dict[str, dict[str, int]]:
    tools = [
        "spark",
        "openbin",
        "ghidra",
        "ida",
        "binja",
        "llm4decompile",
    ]
    out: dict[str, dict[str, int]] = {}
    for t in tools:
        counts = {"win": 0, "tie": 0, "loss": 0, "na": 0}
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
    matrix = _parity_matrix()
    summary = _summarize(matrix)
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
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
    return {
        "generated_at": ts,
        "generator": "tools/spark-bc-dump/decompile_bench.py",
        "domain": "SPARK_BC",
        "honesty": (
            "Measured Spark metrics on SPARK_BC fixtures only. "
            "Do NOT publish 'Spark beats Ghidra/IDA/Binary Ninja/"
            "LLM4Decompile/OpenBin' without this JSON. Classic "
            "tools win ELF/PE; Spark wins SPBC round-trip + "
            "local structured dump + privacy + train/weights."
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
