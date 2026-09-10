"""Unit tests for voice-loop companions (synthetic fixtures)."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from sparklang.voice_loop.bench import run_bench
from sparklang.voice_loop.expect_score import run_expect_score
from sparklang.voice_loop.ground_stmt import run_ground_fact
from sparklang.voice_loop.pairs import run_pairs
from sparklang.voice_loop.schedule import run_schedule_nightly
from sparklang.voice_loop.stmt import dispatch_stmt

ROOT = Path(__file__).resolve().parents[2]
TURNS = "examples/fixtures/voice_loop/turns.jsonl"
FACTS = "examples/fixtures/voice_loop/facts.json"
HELPER = "examples/fixtures/voice_loop/agents/agent-a"


class VoiceLoopTests(unittest.TestCase):
    """CPU dry-run coverage for voice-loop primitives."""

    @classmethod
    def setUpClass(cls) -> None:
        """Require repo root cwd."""
        import os

        os.chdir(ROOT)

    def test_pairs_filter(self) -> None:
        """pairs filters stall + min_gap."""
        p = run_pairs(
            TURNS,
            class_eq="stall",
            min_gap=2,
            dry=True,
        )
        self.assertEqual(p["op"], "pairs")
        self.assertGreaterEqual(p["n_out"], 1)
        self.assertTrue(p["pref_inputs"])

    def test_expect_score_pass(self) -> None:
        """helper beats empty baseline."""
        p = run_expect_score(
            "examples/fixtures/voice_loop/*.spark",
            HELPER,
            "out/none",
            dry=True,
        )
        self.assertTrue(p["pass"])

    def test_ground_hit_and_miss(self) -> None:
        """ground returns value or abstains."""
        hit = run_ground_fact("price", FACTS, dry=True)
        self.assertFalse(hit["abstain"])
        miss = run_ground_fact("nope", FACTS, dry=True)
        self.assertTrue(miss["abstain"])

    def test_bench_board(self) -> None:
        """bench writes per-class gap."""
        with tempfile.TemporaryDirectory() as td:
            out = str(Path(td) / "board.json")
            p = run_bench(
                "examples/fixtures/voice_loop/*.spark",
                "agent-a",
                "agent-b",
                out_path=out,
                dry=True,
            )
            self.assertIn("stall", p["board"])
            self.assertTrue(Path(out).is_file())

    def test_schedule_summary(self) -> None:
        """nightly summary artifact."""
        with tempfile.TemporaryDirectory() as td:
            out = str(Path(td) / "sum.json")
            p = run_schedule_nightly(
                "examples/pairs_basic.spark",
                pairs_source=TURNS,
                helper_out=str(Path(td) / "pref"),
                summary_path=out,
                dry=True,
            )
            self.assertTrue(p["ok"])
            self.assertTrue(Path(out).is_file())

    def test_dispatch_pairs_line(self) -> None:
        """stmt dispatcher accepts model pairs line."""
        line = (
            'model pairs from "'
            + TURNS
            + '" schema "context,target_turn,'
            "candidate_turn,score_target,score_candidate,class"
            '" where class = "stall" min_gap 2 -> ds'
        )
        p = dispatch_stmt(line, dry=True)
        self.assertEqual(p["op"], "pairs")


if __name__ == "__main__":
    unittest.main()
