#!/usr/bin/env python3
"""Tests for Spark voice/text ask loop."""

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

from spark_ask.voice_ask import (  # noqa: E402
    answer_question,
    load_context,
    run_ask,
)


class VoiceAskTests(unittest.TestCase):
    """Voice/text ask loads dump context and answers honestly."""

    def setUp(self) -> None:
        """Temp dir + published .sparkbc fixture."""
        self.tmp = Path(tempfile.mkdtemp(prefix="spark-ask-"))
        self.bc = (
            ROOT / "docs" / "examples" / "spark-train-step.sparkbc"
        )
        self.assertTrue(self.bc.is_file(), "missing fixture sparkbc")

    def tearDown(self) -> None:
        """Remove temp tree."""
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_load_sparkbc_context(self) -> None:
        """Load ops + dump from a real .sparkbc."""
        ctx = load_context(self.bc, root=ROOT)
        self.assertEqual(ctx["kind"], "sparkbc")
        self.assertIn("SPBC", ctx["dump_text"])
        self.assertGreater(len(ctx["ops"]), 0)
        self.assertEqual(len(ctx["sha256"]), 64)

    def test_factual_opcodes_question(self) -> None:
        """Dump-fact path answers opcode list without TinyCoder."""
        ctx = load_context(self.bc, root=ROOT)
        out = answer_question(
            "What opcodes are in this dump?",
            ctx,
            root=ROOT,
            weights=self.tmp / "missing.safetensors",
        )
        self.assertEqual(out["engine"], "dump_facts")
        self.assertIn("TRAIN", out["answer"])
        self.assertIn(
            "does not beat claude",
            out["answer"].lower(),
        )

    def test_run_ask_text_dry_speak(self) -> None:
        """--text + --dry writes stub WAV and ASK.md."""
        wav = self.tmp / "reply.wav"
        payload = run_ask(
            self.bc,
            root=ROOT,
            text="List the opcodes please",
            voice=True,
            dry=True,
            wav_out=wav,
            weights=self.tmp / "nope.safetensors",
        )
        self.assertTrue(payload["ok"])
        self.assertFalse(payload["openbin_login"])
        self.assertEqual(payload["tts_mode"], "dry")
        self.assertTrue(wav.is_file())
        self.assertGreater(wav.stat().st_size, 44)
        self.assertTrue(Path(payload["ask_md"]).is_file())

    def test_analysis_dir_context(self) -> None:
        """Load sibling-compatible analysis folder layout."""
        from sparklang.model_lab.bc_dump import (
            decode_ops,
            format_dump,
            load_sparkbc,
        )

        folder = self.tmp / "analyze-demo"
        folder.mkdir()
        bc = load_sparkbc(self.bc)
        dump = format_dump(
            bc,
            source=str(self.bc),
            command="test",
            label="SPARK_BC dump",
        )
        (folder / "dump.txt").write_text(dump, encoding="utf-8")
        ops = decode_ops(bc)
        (folder / "ops.json").write_text(
            json.dumps(
                {
                    "kind": "sparkbc_ops",
                    "sha256": bc["sha256"],
                    "ops": ops,
                }
            ),
            encoding="utf-8",
        )
        shutil.copy2(self.bc, folder / "program.sparkbc")
        ctx = load_context(folder, root=ROOT)
        self.assertEqual(ctx["kind"], "analysis_dir")
        self.assertGreater(len(ctx["ops"]), 0)
        out = answer_question(
            "how many opcodes?",
            ctx,
            root=ROOT,
            weights=self.tmp / "missing.safetensors",
        )
        self.assertEqual(out["engine"], "dump_facts")
        self.assertIn(str(len(ops)), out["answer"])


if __name__ == "__main__":
    raise SystemExit(unittest.main())
