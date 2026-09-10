#!/usr/bin/env python3
"""JS/Python SPARK_BC parser parity gate.

Runs the website's client-side parser (``website/js/sparkbc.js`` —
the exact file served on /ide-web.html) under node against the
published fixtures and asserts byte-identical dump text plus an
identical structured analysis vs ``bc_dump.py``. Also asserts both
sides fail loud on bad magic. No canned text anywhere in the loop.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python"))

from sparklang.model_lab.bc_dump import (  # noqa: E402
    analyze_bc,
    format_dump,
    load_sparkbc,
)

JS_BRIDGE = ROOT / "tools/spark-bc-dump/js_parity.js"

FIXTURES = [
    {
        "path": ROOT / "docs/examples/spark-train-step.sparkbc",
        "source": "examples/spark_train_step.spark",
        "command": (
            "./spark-bootstrap --compile "
            "examples/spark_train_step.spark "
            "-o docs/examples/spark-train-step.sparkbc"
        ),
        "label": "parity train-step",
    },
    {
        "path": ROOT / "docs/examples/spark-builder.sparkbc",
        "source": "examples/spark_builder.spark",
        "command": (
            "./spark-bootstrap --compile examples/spark_builder.spark "
            "-o docs/examples/spark-builder.sparkbc"
        ),
        "label": "parity builder",
    },
    {
        "path": ROOT / "docs/examples/spark-self.sparkbc",
        "source": "selfhost/compile.spark",
        "command": (
            "./spark-bootstrap --compile selfhost/compile.spark "
            "-o docs/examples/spark-self.sparkbc"
        ),
        "label": "parity self",
    },
]


def _node() -> str:
    node = shutil.which("node")
    if not node:
        raise RuntimeError(
            "node not on PATH — required for the JS parser parity gate"
        )
    return node


def _js_side(fixture: dict[str, str]) -> dict[str, object]:
    proc = subprocess.run(
        [
            _node(),
            str(JS_BRIDGE),
            str(fixture["path"]),
            "--source",
            fixture["source"],
            "--command",
            fixture["command"],
            "--label",
            fixture["label"],
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            "js_parity bridge failed rc=%d stderr=%s"
            % (proc.returncode, proc.stderr[-400:])
        )
    return json.loads(proc.stdout)


def _py_side(fixture: dict[str, str]) -> dict[str, object]:
    bc = load_sparkbc(fixture["path"])
    dump = format_dump(
        bc,
        source=fixture["source"],
        command=fixture["command"],
        label=fixture["label"],
    )
    analysis = analyze_bc(bc)
    analysis.pop("path", None)  # JS side is path-free (browser bytes)
    return {"dump": dump, "analysis": analysis}


def test_dump_text_byte_identical() -> None:
    """formatDump JS output == format_dump Python output."""
    for fixture in FIXTURES:
        js = _js_side(fixture)
        py = _py_side(fixture)
        assert js["dump"] == py["dump"], (
            "dump text mismatch on %s" % fixture["path"]
        )


def test_analysis_identical() -> None:
    """analyzeBc JS output == analyze_bc Python output."""
    for fixture in FIXTURES:
        js = _js_side(fixture)
        py = _py_side(fixture)
        assert js["analysis"] == py["analysis"], (
            "analysis mismatch on %s" % fixture["path"]
        )


def test_bad_magic_fails_loud_both_sides() -> None:
    """Truncated/garbage input errors on both parsers."""
    with tempfile.TemporaryDirectory(prefix="spark-parity-") as td:
        bad = Path(td) / "bad.sparkbc"
        bad.write_bytes(b"NOPE\x01\x00\x00garbage")
        proc = subprocess.run(
            [_node(), str(JS_BRIDGE), str(bad)],
            capture_output=True,
            text=True,
            check=False,
        )
        assert proc.returncode != 0
        assert "bad magic" in proc.stderr
        try:
            load_sparkbc(bad)
        except ValueError as exc:
            assert "bad magic" in str(exc)
        else:
            raise AssertionError("python parser accepted bad magic")


def main() -> int:
    """Run the JS/Python parser parity gates."""
    test_dump_text_byte_identical()
    test_analysis_identical()
    test_bad_magic_fails_loud_both_sides()
    print("ok test_js_parity (%d fixtures)" % len(FIXTURES))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
