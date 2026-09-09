#!/usr/bin/env python3
"""Unit tests for spark-eval + optional Claude baseline honesty."""

from __future__ import annotations

import json
import os
import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
EVAL = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "python"))
sys.path.insert(0, str(EVAL))

import claude_baseline as cb  # noqa: E402
import run as spark_eval  # noqa: E402


class DiscoverKeyTests(unittest.TestCase):
    """Credential discovery never invents keys."""

    def test_unset_skips(self) -> None:
        """No env → skipped_no_credentials."""
        with mock.patch.dict(os.environ, {}, clear=True):
            key, status = cb.discover_claude_api_key()
        self.assertIsNone(key)
        self.assertEqual(status, "skipped_no_credentials")

    def test_env_key(self) -> None:
        """ANTHROPIC_API_KEY is accepted when set."""
        env = {"ANTHROPIC_API_KEY": "sk-test-not-real"}
        with mock.patch.dict(os.environ, env, clear=True):
            key, status = cb.discover_claude_api_key()
        self.assertEqual(key, "sk-test-not-real")
        self.assertTrue(status.startswith("credentials_env:"))


class ClaudeBaselineHonestyTests(unittest.TestCase):
    """Baseline never upgrades claim / beats_claude."""

    def test_auto_skip_without_creds(self) -> None:
        """auto + no key → skip status, beats_claude false."""
        probes = [
            {
                "name": "copy_recall",
                "kind": "copy_recall",
                "fixture": "examples/eval/fixtures/copy_recall.jsonl",
                "metric": "token_accuracy",
            }
        ]

        def load(_fix: str) -> list[dict]:
            return [{"prompt": "x", "want": "y"}]

        with mock.patch.dict(os.environ, {}, clear=True):
            out = cb.run_claude_baseline(
                probes, load, mode="auto"
            )
        self.assertEqual(out["status"], "skipped_no_credentials")
        self.assertIs(out["beats_claude"], False)
        self.assertEqual(out["claim"], "none")

    def test_on_missing_creds_status(self) -> None:
        """on + no key → error field, still no win claim."""
        with mock.patch.dict(os.environ, {}, clear=True):
            out = cb.run_claude_baseline(
                [], lambda _: [], mode="on"
            )
        self.assertEqual(out["status"], "skipped_no_credentials")
        self.assertIn("error", out)
        self.assertIs(out["beats_claude"], False)

    def test_ran_still_not_beat(self) -> None:
        """Even with mocked Claude scores, beats_claude stays False."""

        class _Resp:
            def __enter__(self) -> "_Resp":
                return self

            def __exit__(self, *a: object) -> None:
                return None

            def read(self) -> bytes:
                body = {
                    "content": [
                        {"type": "text", "text": "spark"}
                    ]
                }
                return json.dumps(body).encode("utf-8")

        def opener(_req: object, timeout: int = 0) -> _Resp:
            return _Resp()

        probes = [
            {
                "name": "copy_recall",
                "kind": "copy_recall",
                "fixture": "x.jsonl",
                "metric": "token_accuracy",
            }
        ]

        def load(_f: str) -> list[dict]:
            return [{"prompt": "Say exactly: spark", "want": "spark"}]

        env = {"ANTHROPIC_API_KEY": "sk-test"}
        with mock.patch.dict(os.environ, env, clear=True):
            out = cb.run_claude_baseline(
                probes, load, mode="auto", opener=opener
            )
        self.assertEqual(out["status"], "ran")
        self.assertEqual(out["probes"][0]["score"], 1.0)
        self.assertIs(out["beats_claude"], False)
        self.assertEqual(out["claim"], "none")

    def test_comparison_never_claims_win(self) -> None:
        """Spark higher than Claude still claim none."""
        spark = [{"name": "a", "score": 1.0}]
        claude = {
            "probes": [{"name": "a", "score": 0.0}],
            "beats_claude": False,
        }
        table = cb.comparison_table(spark, claude)
        self.assertIs(table["beats_claude"], False)
        self.assertEqual(table["claim"], "none")
        self.assertEqual(table["rows"][0]["spark_score"], 1.0)
        self.assertEqual(table["rows"][0]["claude_score"], 0.0)


class RunSuiteTests(unittest.TestCase):
    """End-to-end suite dry path + Claude auto skip."""

    def test_dry_suite_claude_auto_skip(self) -> None:
        """make spark-eval CLAUDE=auto without keys stays honest."""
        with mock.patch.dict(os.environ, {}, clear=True):
            result = spark_eval.run_suite(
                spark_eval.SUITE_DEFAULT,
                None,
                claude_mode="auto",
            )
        self.assertEqual(result["claim"], "none")
        self.assertIs(result["beats_claude"], False)
        self.assertEqual(result["mode"], "dry")
        self.assertEqual(len(result["probes"]), 2)
        for p in result["probes"]:
            self.assertEqual(p["score"], 1.0)
            self.assertEqual(p["system"], "spark")
        base = result["claude_baseline"]
        self.assertEqual(base["status"], "skipped_no_credentials")
        self.assertIs(base["beats_claude"], False)

    def test_weights_mode_runs(self) -> None:
        """Init safetensors path still scores (often 0.0)."""
        weights = (
            ROOT / "docs/examples/spark-self.init.safetensors"
        )
        if not weights.is_file():
            self.skipTest("init safetensors missing")
        with mock.patch.dict(os.environ, {}, clear=True):
            result = spark_eval.run_suite(
                spark_eval.SUITE_DEFAULT,
                weights,
                claude_mode="off",
            )
        self.assertEqual(result["mode"], "weights")
        self.assertEqual(result["claim"], "none")
        self.assertIs(result["beats_claude"], False)
        self.assertEqual(
            result["claude_baseline"]["status"], "off"
        )


if __name__ == "__main__":
    raise SystemExit(unittest.main())
