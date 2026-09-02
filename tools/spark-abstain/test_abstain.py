"""Unit tests for SparkLang abstain gate / parse / train."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python"))

from sparklang.abstain.dry import dry_result  # noqa: E402
from sparklang.abstain.gate import (  # noqa: E402
    GateConfig,
    select_before_sample,
)
from sparklang.abstain.parse import parse_head_stmt  # noqa: E402
from sparklang.abstain.train import train_abstain_head  # noqa: E402


class GateTests(unittest.TestCase):
    """Threshold / entropy / margin SELECT logic."""

    def test_threshold_abstain(self) -> None:
        d = select_before_sample(0.8, GateConfig(threshold=0.7))
        self.assertTrue(d.abstain)
        self.assertTrue(d.halted)
        self.assertEqual(d.reason, "threshold")
        self.assertEqual(d.text, "I don't know.")

    def test_threshold_continue(self) -> None:
        d = select_before_sample(0.2, GateConfig(threshold=0.7))
        self.assertFalse(d.abstain)
        self.assertFalse(d.halted)
        self.assertEqual(d.reason, "continue")
        self.assertIsNone(d.text)

    def test_entropy_trip(self) -> None:
        cfg = GateConfig(threshold=0.99, entropy_max=1.5)
        d = select_before_sample(0.1, cfg, entropy=2.0)
        self.assertTrue(d.abstain)
        self.assertEqual(d.reason, "entropy")

    def test_margin_trip(self) -> None:
        cfg = GateConfig(threshold=0.99, margin_min=0.2)
        d = select_before_sample(0.1, cfg, margin=0.05)
        self.assertTrue(d.abstain)
        self.assertEqual(d.reason, "margin")


class ParseTests(unittest.TestCase):
    """``.spark`` head statement parsing."""

    def test_abstain_internal(self) -> None:
        f = parse_head_stmt(
            'head abstain internal model "m" '
            'weights "w.pt" threshold 0.7 '
            'idk "I don\'t know." -> gate'
        )
        self.assertEqual(f["op"], "abstain")
        self.assertEqual(f["kind"], "internal")
        self.assertEqual(f["model"], "m")
        self.assertEqual(f["threshold"], 0.7)
        self.assertEqual(f["bind"], "gate")

    def test_ask(self) -> None:
        f = parse_head_stmt(
            'head ask "Who is the mayor?" -> answer'
        )
        self.assertEqual(f["op"], "ask")
        self.assertIn("mayor", f["prompt"])
        self.assertEqual(f["bind"], "answer")

    def test_train(self) -> None:
        f = parse_head_stmt(
            'head train dataset "d.jsonl" kind external '
            'out "o.pt" hidden_dim 64 -> job'
        )
        self.assertEqual(f["op"], "train")
        self.assertEqual(f["kind"], "external")
        self.assertEqual(f["hidden_dim"], 64)


class DryAskTests(unittest.TestCase):
    """Dry ask inventable → abstain."""

    def test_mayor_abstains(self) -> None:
        r = dry_result(
            {
                "op": "ask",
                "prompt": "Who is the mayor of Springfield?",
            }
        )
        self.assertTrue(r["abstain"])
        self.assertTrue(r["halted"])


class TrainTests(unittest.TestCase):
    """CPU train writes a real .pt."""

    def test_train_fixture(self) -> None:
        ds = ROOT / "examples/fixtures/abstain/labels.jsonl"
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "h.pt"
            info = train_abstain_head(
                ds, out, kind="internal", steps=50, hidden_dim=64
            )
            self.assertEqual(info["state"], "succeeded")
            self.assertTrue(out.is_file())
            meta = out.with_suffix(".meta.json")
            self.assertTrue(meta.is_file())
            body = json.loads(meta.read_text(encoding="utf-8"))
            self.assertEqual(body["spark"], "abstain_head")


if __name__ == "__main__":
    unittest.main()
