#!/usr/bin/env python3
"""Compile → dump → recompile hash gate for SPARK_BC fixtures.

SoT win Spark already has: deterministic ``--compile`` bytes.
Dump sits in the middle as inspect proof — not source recovery.
No frontier-parity claim. Never 6000.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT / "python") not in sys.path:
    sys.path.insert(0, str(ROOT / "python"))

from sparklang.model_lab.bc_dump import (  # noqa: E402
    analyze_bc,
    format_dump,
    load_sparkbc,
)

# Published fixture map: source → published .sparkbc
FIXTURES: list[dict[str, str]] = [
    {
        "id": "train-step",
        "source": "examples/spark_train_step.spark",
        "published": "docs/examples/spark-train-step.sparkbc",
    },
    {
        "id": "builder",
        "source": "examples/spark_builder.spark",
        "published": "docs/examples/spark-builder.sparkbc",
    },
    {
        "id": "self",
        "source": "selfhost/compile.spark",
        "published": "docs/examples/spark-self.sparkbc",
    },
]


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _compile(boot: Path, source: Path, out: Path) -> None:
    """Run spark-bootstrap --compile."""
    cmd = [str(boot), "--compile", str(source), "-o", str(out)]
    proc = subprocess.run(
        cmd,
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0 or not out.is_file():
        raise RuntimeError(
            "compile failed rc=%d stderr=%s"
            % (proc.returncode, proc.stderr[-400:])
        )


def verify_one(
    *,
    boot: Path,
    fixture: dict[str, str],
    dump_dir: Path | None,
) -> dict[str, object]:
    """Compile twice, dump once, assert equal hashes."""
    src = ROOT / fixture["source"]
    pub = ROOT / fixture["published"]
    if not src.is_file():
        return {
            "id": fixture["id"],
            "status": "fail",
            "error": "missing source %s" % src,
        }
    if not pub.is_file():
        return {
            "id": fixture["id"],
            "status": "fail",
            "error": "missing published %s" % pub,
        }
    with tempfile.TemporaryDirectory(prefix="spark-rt-") as td:
        tdir = Path(td)
        a = tdir / "a.sparkbc"
        b = tdir / "b.sparkbc"
        _compile(boot, src, a)
        bc = load_sparkbc(a)
        analysis = analyze_bc(bc)
        dump_text = format_dump(
            bc,
            source=fixture["source"],
            command=(
                "./spark-bootstrap --compile %s -o %s"
                % (fixture["source"], fixture["published"])
            ),
            label="roundtrip %s" % fixture["id"],
        )
        if dump_dir is not None:
            dump_dir.mkdir(parents=True, exist_ok=True)
            (dump_dir / ("%s-bc.txt" % fixture["id"])).write_text(
                dump_text, encoding="utf-8"
            )
        _compile(boot, src, b)
        sha_a = _sha256(a)
        sha_b = _sha256(b)
        sha_pub = _sha256(pub)
        ok = sha_a == sha_b == sha_pub == bc["sha256"]
        return {
            "id": fixture["id"],
            "status": "pass" if ok else "fail",
            "source": fixture["source"],
            "published": fixture["published"],
            "sha256": sha_a,
            "recompile_match": sha_a == sha_b,
            "published_match": sha_a == sha_pub,
            "n_ops": analysis["xrefs"]["n_ops"],
            "n_symbols": len(analysis["symbols"]),
            "n_sections": len(analysis["sections"]),
            "dump_bytes": len(dump_text.encode("utf-8")),
        }


def run_all(
    *,
    boot: Path | None = None,
    dump_dir: Path | None = None,
    fixture_ids: list[str] | None = None,
) -> dict[str, object]:
    """Verify all (or selected) fixtures; return scoreboard dict."""
    boot_path = boot or (ROOT / "spark-bootstrap")
    if not boot_path.is_file():
        return {
            "status": "fail",
            "error": "missing spark-bootstrap (make spark-bootstrap)",
            "fixtures": [],
            "round_trip_pct": 0.0,
        }
    selected = FIXTURES
    if fixture_ids:
        want = set(fixture_ids)
        selected = [f for f in FIXTURES if f["id"] in want]
    rows = [
        verify_one(boot=boot_path, fixture=f, dump_dir=dump_dir)
        for f in selected
    ]
    n_ok = sum(1 for r in rows if r.get("status") == "pass")
    n = len(rows) or 1
    return {
        "status": "pass" if n_ok == len(rows) else "fail",
        "domain": "SPARK_BC",
        "round_trip_pct": round(100.0 * n_ok / n, 2),
        "n_pass": n_ok,
        "n_total": len(rows),
        "fixtures": rows,
        "note": (
            "compile→dump→recompile hash on same .spark source; "
            "dump is inspect, not source decompile"
        ),
    }


def main(argv: list[str] | None = None) -> int:
    """CLI entry for round-trip verify."""
    p = argparse.ArgumentParser(prog="spark-bc-roundtrip")
    p.add_argument(
        "--json-out",
        help="write result JSON here",
    )
    p.add_argument(
        "--dump-dir",
        help="optional dir for per-fixture dump text",
    )
    p.add_argument(
        "--fixture",
        action="append",
        help="fixture id (repeatable); default all",
    )
    args = p.parse_args(argv)
    dump_dir = Path(args.dump_dir) if args.dump_dir else None
    result = run_all(dump_dir=dump_dir, fixture_ids=args.fixture)
    text = json.dumps(result, indent=2) + "\n"
    if args.json_out:
        out = Path(args.json_out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(text, encoding="utf-8")
        print("wrote %s" % out)
    else:
        sys.stdout.write(text)
    return 0 if result.get("status") == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
