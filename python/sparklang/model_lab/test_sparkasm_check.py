"""Tests for .sparkasm shape-check stub (no tensor VM)."""

from __future__ import annotations

import unittest
from pathlib import Path

from sparklang.model_lab.sparkasm_check import (
    check_control,
    check_file,
    parse_sparkasm,
)

ROOT = Path(__file__).resolve().parents[3]
CONTROL = ROOT / "examples" / "models" / "control.sparkasm"


class TestSparkasmCheck(unittest.TestCase):
    """Control source parses and passes GQA/shape invariants."""

    def test_control_file_ok(self) -> None:
        """examples/models/control.sparkasm is shape-clean."""
        self.assertTrue(CONTROL.is_file(), "missing %s" % CONTROL)
        errs = check_file(CONTROL)
        self.assertEqual(errs, [], errs)

    def test_gqa_reject(self) -> None:
        """H not divisible by KV fails loudly."""
        bad = CONTROL.read_text(encoding="utf-8").replace(
            ".dim KV = 2",
            ".dim KV = 3",
        )
        errs = check_control(parse_sparkasm(bad))
        self.assertTrue(any("GQA" in e for e in errs), errs)


if __name__ == "__main__":
    unittest.main()
