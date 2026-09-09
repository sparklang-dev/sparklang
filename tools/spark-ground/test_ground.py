"""Unit tests for spark-ground anti-guess gates."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python"))

from sparklang.ground.adapter import (  # noqa: E402
    AdapterSpec,
    attach_adapter_manifest,
)
from sparklang.ground.gate import (  # noqa: E402
    grounded_ask,
    verify_before_speak,
)
from sparklang.ground.schema import validate_json_schema  # noqa: E402


class SchemaTests(unittest.TestCase):
    """Minimal JSON schema subset."""

    def test_ok(self) -> None:
        ok, err = validate_json_schema(
            {"price_usd": 2.5},
            {
                "type": "object",
                "required": ["price_usd"],
                "properties": {
                    "price_usd": {"type": "number"},
                },
            },
        )
        self.assertTrue(ok)
        self.assertIsNone(err)

    def test_type_miss(self) -> None:
        ok, err = validate_json_schema(
            {"price_usd": "x"},
            {
                "type": "object",
                "properties": {
                    "price_usd": {"type": "number"},
                },
            },
        )
        self.assertFalse(ok)
        self.assertIn("type", err or "")


class VerifyTests(unittest.TestCase):
    """Wrong expect must abstain."""

    def test_wrong_expect_abstains(self) -> None:
        r = verify_before_speak(
            "9.99",
            expect="2.50",
            expect_mode="equal",
        )
        self.assertTrue(r["abstain"])
        self.assertTrue(r["halted"])
        self.assertEqual(r["reason"], "expect_equal_miss")
        self.assertEqual(r["text"], "I don't know.")

    def test_match_passes(self) -> None:
        r = verify_before_speak("2.50", expect="2.50")
        self.assertFalse(r["abstain"])
        self.assertEqual(r["reason"], "verified")

    def test_fixture_miss(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            fx = Path(td) / "want.txt"
            fx.write_text("Ada Lovelace\n", encoding="utf-8")
            r = verify_before_speak(
                "Someone Else",
                fixture=fx,
                expect_mode="equal",
            )
            self.assertTrue(r["abstain"])
            self.assertEqual(r["reason"], "expect_equal_miss")

    def test_ungrounded_refuses(self) -> None:
        r = verify_before_speak("hello world")
        self.assertTrue(r["abstain"])
        self.assertEqual(r["reason"], "ungrounded")

    def test_schema_fail(self) -> None:
        r = verify_before_speak(
            '{"price_usd":"nope"}',
            schema={
                "type": "object",
                "required": ["price_usd"],
                "properties": {
                    "price_usd": {"type": "number"},
                },
            },
        )
        self.assertTrue(r["abstain"])
        self.assertIn("schema", r["reason"])


class GroundedAskTests(unittest.TestCase):
    """Inventable + tool allowlist."""

    def test_inventable_without_sot(self) -> None:
        r = grounded_ask(
            "Who is the mayor of Springfield?",
            candidate="Mayor X",
            expect="Mayor X",
        )
        self.assertTrue(r["abstain"])
        self.assertEqual(r["reason"], "outer_verify")

    def test_tool_denied(self) -> None:
        r = grounded_ask(
            "ping",
            candidate="pong",
            expect="pong",
            tool_requested="shell",
            tool_allowlist=["http"],
            require_ground=True,
        )
        self.assertTrue(r["abstain"])
        self.assertEqual(r["reason"], "tool_denied")

    def test_sot_and_expect(self) -> None:
        r = grounded_ask(
            "What is the dryer start price right now?",
            candidate="2.50",
            expect="2.50",
            sot_ok=True,
        )
        self.assertFalse(r["abstain"])
        self.assertEqual(r["text"], "2.50")


class AdapterTests(unittest.TestCase):
    """Attach-only manifest."""

    def test_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "m.json"
            payload = attach_adapter_manifest(
                base="qwen",
                keep_existing="out/train/existing-lora",
                add=[
                    AdapterSpec(
                        path="out/train/job/adapter.bin",
                    ),
                ],
                out=out,
            )
            self.assertTrue(payload["keep_special_training"])
            self.assertEqual(
                payload["device_policy"]["never"], "6000"
            )
            disk = json.loads(out.read_text(encoding="utf-8"))
            self.assertEqual(disk["op"], "adapter_attach")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
