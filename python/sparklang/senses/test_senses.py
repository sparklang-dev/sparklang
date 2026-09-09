"""Unit tests for planned vision sense stubs."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from sparklang.senses.vision import (
    VisionRequest,
    VisionStatus,
    default_status,
    look,
    sense_name,
)
from sparklang.senses import voice_train_hint


class TestVisionSense(unittest.TestCase):
    """Eyes stay planned — no fake captions from weights."""

    def test_sense_name(self) -> None:
        """Label is eyes."""
        self.assertEqual(sense_name(), "eyes")

    def test_default_status_planned(self) -> None:
        """Tip status is planned."""
        self.assertEqual(default_status(), VisionStatus.PLANNED)

    def test_look_dry_empty_caption(self) -> None:
        """Dry look never invents a caption."""
        req = VisionRequest(path=Path("missing.png"), dry_run=True)
        out = look(req)
        self.assertEqual(out.status, VisionStatus.PLANNED)
        self.assertEqual(out.caption, "")
        self.assertIn("not in Spark runtime", out.detail)

    def test_look_existing_file_still_planned(self) -> None:
        """Even with a real file, encoder is not claimed."""
        with tempfile.NamedTemporaryFile(suffix=".png") as tmp:
            path = Path(tmp.name)
            req = VisionRequest(path=path, dry_run=False)
            out = look(req)
            self.assertEqual(out.status, VisionStatus.PLANNED)
            self.assertEqual(out.caption, "")
            self.assertIn("not shipped", out.detail)

    def test_voice_train_hint(self) -> None:
        """Ears/speaking train path points at voice-easy."""
        hint = voice_train_hint()
        self.assertIn("spark-voice", hint["train"])
        self.assertEqual(hint["never"], "rtx-pro-6000")


if __name__ == "__main__":
    unittest.main()
