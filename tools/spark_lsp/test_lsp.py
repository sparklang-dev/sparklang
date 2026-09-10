#!/usr/bin/env python3
"""Unit tests for SparkLang LSP analyze helpers."""

from __future__ import annotations

import json
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

from analyze import completions, diagnose, hover_for  # noqa: E402


class TestSparkLsp(unittest.TestCase):
    """Static diagnostics + hover/completion smoke."""

    def test_unbound_expect_is_error(self) -> None:
        """expect on missing bind must Error."""
        text = 'expect equal missing "x"\n'
        diags = diagnose(text)
        codes = {d["code"] for d in diags}
        self.assertIn("expect-unbound", codes)
        self.assertTrue(
            any(d["severity"] == "Error" for d in diags)
        )

    def test_bound_expect_ok(self) -> None:
        """let + expect equal passes without Error."""
        text = 'let answer "Ada"\nexpect equal answer "Ada"\n'
        diags = diagnose(text)
        self.assertFalse(
            any(d["code"] == "expect-unbound" for d in diags)
        )

    def test_unclosed_string_warning(self) -> None:
        """Odd quote count on a line → Warning."""
        text = 'print "hello\n'
        diags = diagnose(text)
        self.assertTrue(
            any(d["code"] == "unclosed-string" for d in diags)
        )

    def test_hover_ask(self) -> None:
        """Hover returns markdown for ask."""
        md = hover_for("ask")
        self.assertIsNotNone(md)
        assert md is not None
        self.assertIn("ask", md.lower())

    def test_completions_include_expect(self) -> None:
        """Completion list includes expect."""
        labels = {c["label"] for c in completions("ex")}
        self.assertIn("expect", labels)

    def test_check_cli_json(self) -> None:
        """--check emits JSON with diagnostics key."""
        sample = ROOT / "examples" / "expect_pass.spark"
        proc = subprocess.run(
            [
                sys.executable,
                str(ROOT / "tools" / "spark_lsp" / "server.py"),
                "--check",
                str(sample),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        payload = json.loads(proc.stdout)
        self.assertIn("diagnostics", payload)


if __name__ == "__main__":
    unittest.main()
