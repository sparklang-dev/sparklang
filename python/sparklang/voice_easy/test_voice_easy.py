"""Unit + dry integration tests for voice-easy (CI)."""

from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path

from sparklang.voice_easy.device import (
    VoiceDeviceError,
    pick_voice_device,
)
from sparklang.voice_easy.pipeline import check_env, run_easy
from sparklang.voice_easy.scales import resolve_scale
from sparklang.voice_easy.train import train_voice_easy


class TestVoiceEasyScales(unittest.TestCase):
    """Scale resolution and honesty flags."""

    def test_default_tiny(self) -> None:
        """Default scale is tiny."""
        cfg = resolve_scale(None, env={})
        self.assertEqual(cfg["name"], "tiny")
        self.assertFalse(cfg["beats_claude"])
        self.assertEqual(cfg["never"], "rtx-pro-6000")

    def test_env_large(self) -> None:
        """VOICE_SCALE=large resolves."""
        cfg = resolve_scale(None, env={"VOICE_SCALE": "large"})
        self.assertEqual(cfg["name"], "large")
        self.assertGreater(cfg["dim"], 64)
        self.assertTrue(cfg["require_5090"])

    def test_bad_scale(self) -> None:
        """Unknown scale raises."""
        with self.assertRaises(ValueError):
            resolve_scale("mega")


class TestVoiceEasyDevice(unittest.TestCase):
    """Never 6000; large fail-closed when forced 5090 missing."""

    def test_cpu_force(self) -> None:
        """Explicit cpu always works."""
        scale = resolve_scale("large")
        pick = pick_voice_device(scale=scale, force="cpu")
        self.assertEqual(pick["device"], "cpu")
        self.assertEqual(pick["never"], "rtx-pro-6000")

    def test_tiny_auto_ok(self) -> None:
        """Tiny auto never raises."""
        scale = resolve_scale("tiny")
        pick = pick_voice_device(scale=scale, force="auto")
        self.assertIn(pick["device"], ("cpu", "cuda"))


class TestVoiceEasyTrainDry(unittest.TestCase):
    """Dry tiny train + roundtrip stays CI-fast."""

    def test_run_easy_dry_tiny(self) -> None:
        """Full easy path under tmp — dry tiny."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result = run_easy(
                root=root,
                scale="tiny",
                device="cpu",
                dry=True,
            )
            self.assertTrue(result["ok"], result)
            self.assertTrue(result["train"]["trained"])
            self.assertGreaterEqual(result["prove"]["stt_acc"], 0.5)
            self.assertEqual(result["prove"]["tts_acc"], 1.0)
            weights = Path(result["train"]["weights"])
            self.assertTrue(weights.is_file())
            self.assertFalse(result["beats_claude"])

    def test_large_cpu_explicit(self) -> None:
        """Large may run on CPU when forced (still owned weights)."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            out = root / "models" / "spark-voice-easy"
            fix = root / "fixtures"
            # Fewer steps via dry clamp for CI time.
            result = train_voice_easy(
                out_dir=out,
                fixture_dir=fix,
                scale_name="large",
                device="cpu",
                dry=True,
            )
            self.assertTrue(result.get("trained"), result)
            self.assertEqual(result["scale"], "large")
            self.assertEqual(result["never"], "rtx-pro-6000")


class TestVoiceEasyEnv(unittest.TestCase):
    """Env check never prints secrets."""

    def test_check_env(self) -> None:
        """Env probe returns ok without keys."""
        info = check_env(dry=True)
        self.assertTrue(info["ok"])
        self.assertNotIn("api_key", str(info).lower())
        self.assertEqual(info["never"], "rtx-pro-6000")


if __name__ == "__main__":
    unittest.main()
