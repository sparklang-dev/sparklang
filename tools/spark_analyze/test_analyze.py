#!/usr/bin/env python3
"""Tests for tools/spark_analyze — local analysis folders."""

from __future__ import annotations

import json
import shutil
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
import sys

sys.path.insert(0, str(ROOT / "python"))
sys.path.insert(0, str(ROOT / "tools"))

from spark_analyze.analyze import find_bootstrap, run_analyze


class AnalyzeLoopTests(unittest.TestCase):
    """Project-loop analyze writes dump + ops + report locally."""

    def setUp(self) -> None:
        """Create a temp out dir; require a published .sparkbc fixture."""
        self.tmp = Path(tempfile.mkdtemp(prefix="spark-analyze-"))
        self.bc = ROOT / "docs" / "examples" / "spark-train-step.sparkbc"
        self.assertTrue(self.bc.is_file(), "missing fixture sparkbc")

    def tearDown(self) -> None:
        """Remove temp analysis tree."""
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_analyze_sparkbc_folder(self) -> None:
        """Dump, ops.json, REPORT, META from a real .sparkbc."""
        out = self.tmp / "folder"
        meta = run_analyze(self.bc, out_dir=out, root=ROOT)
        self.assertTrue(meta["ok"])
        self.assertFalse(meta["uploads"])
        self.assertFalse(meta["beats_claude"])
        self.assertGreater(meta["ops"], 0)
        self.assertTrue((out / "program.sparkbc").is_file())
        self.assertTrue((out / "dump.txt").is_file())
        self.assertTrue((out / "ops.json").is_file())
        self.assertTrue((out / "REPORT.md").is_file())
        self.assertTrue((out / "META.json").is_file())
        self.assertTrue(
            (out / "screenshot.placeholder.md").is_file()
        )
        dump = (out / "dump.txt").read_text(encoding="utf-8")
        self.assertIn("SPBC", dump)
        self.assertIn(meta["sha256"], dump)
        ops = json.loads((out / "ops.json").read_text(encoding="utf-8"))
        self.assertEqual(ops["kind"], "sparkbc_ops")
        self.assertEqual(len(ops["ops"]), meta["ops"])
        names = {row["name"] for row in ops["ops"]}
        self.assertIn("TRAIN", names)

    def test_ask_without_weights_writes_honesty(self) -> None:
        """--ask with missing weights still writes ASK.md notes."""
        out = self.tmp / "ask-miss"
        missing = self.tmp / "no-weights.safetensors"
        meta = run_analyze(
            self.bc,
            out_dir=out,
            root=ROOT,
            ask=True,
            weights=missing,
        )
        self.assertEqual(meta["ask_status"], "no_weights")
        ask = (out / "ASK.md").read_text(encoding="utf-8")
        self.assertIn("capability note", ask.lower())
        self.assertIn("does **not** beat claude", ask.lower())

    def test_ask_with_weights_when_present(self) -> None:
        """Owned TinyCoder path writes ASK.md when weights exist."""
        weights = (
            ROOT / "models" / "spark-coder" / "weights.safetensors"
        )
        if not weights.is_file():
            self.skipTest("spark-coder weights not packaged here")
        out = self.tmp / "ask-hit"
        meta = run_analyze(
            self.bc,
            out_dir=out,
            root=ROOT,
            ask=True,
            weights=weights,
        )
        self.assertIn(meta["ask_status"], ("spark_coder", "error"))
        self.assertTrue((out / "ASK.md").is_file())

    def test_compile_spark_when_bootstrap_present(self) -> None:
        """Compile .spark → analysis folder when bootstrap exists."""
        boot = find_bootstrap(ROOT)
        if boot is None:
            self.skipTest("spark-bootstrap not built in this tree")
        spark = ROOT / "examples" / "spark_train_step.spark"
        if not spark.is_file():
            spark = ROOT / "examples" / "model_improve.spark"
        if not spark.is_file():
            self.skipTest("no small .spark example found")
        out = self.tmp / "from-spark"
        meta = run_analyze(spark, out_dir=out, root=ROOT)
        self.assertTrue(meta["ok"])
        self.assertTrue((out / "source.spark").is_file())
        self.assertTrue((out / "program.sparkbc").is_file())
        self.assertGreater(meta["ops"], 0)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
