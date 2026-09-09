#!/usr/bin/env python3
"""Unit + smoke tests for K-lane helpers / shadows / spark_kit."""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class TestSparkKit(unittest.TestCase):
    """Tool-kit smoke without overnight train."""

    def test_opcode_sheet_has_step(self) -> None:
        """Opcode sheet includes STEP 0x28 from live tables."""
        from spark_kit.opcode_sheet import sheet_text

        text = sheet_text()
        self.assertIn("0x28", text)
        self.assertIn("STEP", text)
        self.assertIn("TRAIN", text)

    def test_fixture_lint_ok(self) -> None:
        """Committed train fixture lints clean."""
        from spark_kit.fixture_lint import lint_jsonl

        path = ROOT / "examples/fixtures/train/dataset.jsonl"
        self.assertEqual(lint_jsonl(path), [])

    def test_fixture_lint_bad(self) -> None:
        """Malformed JSONL fails lint."""
        from spark_kit.fixture_lint import lint_jsonl

        with tempfile.TemporaryDirectory() as tmp:
            bad = Path(tmp) / "bad.jsonl"
            bad.write_text('{"no":"pair"}\n', encoding="utf-8")
            errs = lint_jsonl(bad)
            self.assertTrue(errs)

    def test_hexdump_and_diff_identical(self) -> None:
        """Hexdump + bc_diff on same example BC."""
        from spark_kit.bc_diff import diff_sparkbc
        from spark_kit.hexdump_bc import dump_path

        bc = ROOT / "docs/examples/spark-train-step.sparkbc"
        text = dump_path(bc)
        self.assertIn("sha256=", text)
        # hex of magic S P B C
        self.assertIn("53 50 42 43", text)
        self.assertEqual(diff_sparkbc(bc, bc), 0)

    def test_vocab_inspect(self) -> None:
        """Vocab inspect reads committed spark-bpe-vocab.json."""
        from spark_kit.vocab_inspect import inspect_vocab

        path = ROOT / "docs/examples/spark-bpe-vocab.json"
        text = inspect_vocab(path)
        self.assertIn("spark-bpe-v1", text)
        self.assertIn("vocab_size=", text)


class TestShadow(unittest.TestCase):
    """Shadow copy + verify."""

    def test_copy_and_verify(self) -> None:
        """Shadow copy matches original hash."""
        from spark_shadow.__main__ import cmd_copy, cmd_verify

        src = ROOT / "docs/examples/spark-train-step.sparkbc"
        with tempfile.TemporaryDirectory() as tmp:
            shadow = cmd_copy(src, Path(tmp))
            self.assertEqual(cmd_verify(src, shadow), 0)

    def test_build_dir(self) -> None:
        """build/shadow is created under SPARK_SHADOW_ROOT."""
        from spark_shadow.__main__ import cmd_build_dir

        with tempfile.TemporaryDirectory() as tmp:
            import os

            os.environ["SPARK_SHADOW_ROOT"] = tmp + "/shadow"
            d = cmd_build_dir(create=True)
            self.assertTrue(d.is_dir())
            del os.environ["SPARK_SHADOW_ROOT"]


class TestHelpersCli(unittest.TestCase):
    """Shell helper smoke (needs spark-bootstrap for run)."""

    def test_check_env_script(self) -> None:
        """spark-check-env exits 0 on a built tree or warns only."""
        script = ROOT / "helpers/spark-check-env"
        self.assertTrue(script.is_file())
        proc = subprocess.run(
            ["bash", str(script)],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertIn("spark-check-env", proc.stdout)
        # Missing bootstrap is WARN; imports must pass.
        self.assertEqual(proc.returncode, 0)

    def test_bc_pp_script(self) -> None:
        """spark-bc-pp prints a dump for a real .sparkbc."""
        script = ROOT / "helpers/spark-bc-pp"
        bc = ROOT / "docs/examples/spark-builder.sparkbc"
        proc = subprocess.run(
            ["bash", str(script), str(bc)],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        self.assertTrue(
            "SPARK_BC" in proc.stdout or "HALT" in proc.stdout
            or "sha256" in proc.stdout.lower()
            or len(proc.stdout) > 20
        )


if __name__ == "__main__":
    # Ensure tools/ is importable when run as script.
    import sys

    tools = str(ROOT / "tools")
    if tools not in sys.path:
        sys.path.insert(0, tools)
    py = str(ROOT / "python")
    if py not in sys.path:
        sys.path.insert(0, py)
    unittest.main()
