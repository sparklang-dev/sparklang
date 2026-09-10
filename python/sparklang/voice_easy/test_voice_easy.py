"""Tests for voice-easy on real open weights.

Unit tests always run in CI (no multi-GB downloads): text
normalization, WER/CER math, scales, device guard, fetch manifest
shape, LJSpeech parsing, CLI surface. Integration tests exercise the
real Whisper/Kokoro weights and SKIP with a clear message when the
weights have not been fetched on this box.
"""

from __future__ import annotations

import json
import struct
import sys
import tempfile
import unittest
import wave
from pathlib import Path
from unittest import mock

from sparklang.voice_easy import eval_real
from sparklang.voice_easy.device import pick_voice_device
from sparklang.voice_easy.pipeline import check_env, run_easy
from sparklang.voice_easy.scales import resolve_scale
from sparklang.voice_easy.stt_real import (
    stt_model_dir,
    stt_weights_present,
)
from sparklang.voice_easy.tts_real import tts_weights_present

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "spark-voice"))
import fetch_models  # noqa: E402

SKIP_MSG = (
    "real weights not fetched — run: "
    "python3 tools/spark-voice/fetch_models.py"
)


def _real_deps_present() -> bool:
    """True when faster-whisper + kokoro-onnx are importable."""
    try:
        import faster_whisper  # noqa: F401
        import kokoro_onnx  # noqa: F401
    except ImportError:
        return False
    return True


def _write_test_wav(path: Path, seconds: float = 0.1) -> None:
    """Write a short real PCM WAV on disk for parser unit tests."""
    import math

    rate = 16000
    n = max(1, int(rate * seconds))
    frames = bytearray()
    for i in range(n):
        sample = int(0.2 * math.sin(2 * math.pi * 220 * i / rate)
                     * 32767)
        frames.extend(struct.pack("<h", sample))
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(rate)
        wf.writeframes(bytes(frames))


class TestNormalizeText(unittest.TestCase):
    """Case / punctuation / whitespace normalization."""

    def test_case_and_punct(self) -> None:
        """Normalization strips case and punctuation."""
        self.assertEqual(
            eval_real.normalize_text("Hello, World!  It's... OK?"),
            "hello world its ok",
        )

    def test_whitespace_collapse(self) -> None:
        """Tabs/newlines collapse to single spaces."""
        self.assertEqual(
            eval_real.normalize_text("a\t b\n\n c"), "a b c"
        )

    def test_empty(self) -> None:
        """Empty stays empty."""
        self.assertEqual(eval_real.normalize_text("  "), "")


class TestWerCerMath(unittest.TestCase):
    """Stdlib Levenshtein WER/CER correctness."""

    def test_identical_is_zero(self) -> None:
        """Perfect hypothesis scores 0."""
        self.assertEqual(eval_real.wer("the cat sat", "the cat sat"), 0.0)
        self.assertEqual(eval_real.cer("abc", "abc"), 0.0)

    def test_known_wer(self) -> None:
        """One deletion in four words → WER 0.25."""
        self.assertAlmostEqual(
            eval_real.wer("the cat sat down", "the cat down"), 0.25
        )

    def test_known_cer(self) -> None:
        """One substitution in four chars → CER 0.25."""
        self.assertAlmostEqual(eval_real.cer("abcd", "abxd"), 0.25)

    def test_total_mismatch_caps_sane(self) -> None:
        """Full mismatch on equal length scores 1.0."""
        self.assertEqual(eval_real.wer("a b", "c d"), 1.0)

    def test_empty_ref(self) -> None:
        """Empty ref: empty hyp → 0, non-empty hyp → 1."""
        self.assertEqual(eval_real.wer("", ""), 0.0)
        self.assertEqual(eval_real.wer("", "words"), 1.0)

    def test_normalization_applied(self) -> None:
        """Case/punct differences do not count as errors."""
        self.assertEqual(eval_real.wer("Hello, world!", "hello world"), 0.0)

    def test_bad_unit(self) -> None:
        """Unknown unit raises."""
        with self.assertRaises(ValueError):
            eval_real.error_rate("a", "a", unit="syllable")


class TestScales(unittest.TestCase):
    """Scales mean eval size + model variant — no fake dims."""

    def test_default_tiny(self) -> None:
        """Default scale is tiny."""
        cfg = resolve_scale(None, env={})
        self.assertEqual(cfg["name"], "tiny")
        self.assertEqual(cfg["never"], "rtx-pro-6000")

    def test_env_large(self) -> None:
        """VOICE_SCALE=large resolves."""
        cfg = resolve_scale(None, env={"VOICE_SCALE": "large"})
        self.assertEqual(cfg["name"], "large")
        self.assertEqual(cfg["stt_variant"], "large-v3-turbo")

    def test_bad_scale(self) -> None:
        """Unknown scale raises."""
        with self.assertRaises(ValueError):
            resolve_scale("mega")

    def test_no_fake_dim_concepts(self) -> None:
        """Old fake-head concepts are gone from scale configs."""
        for name in ("tiny", "large"):
            cfg = resolve_scale(name)
            for gone in ("dim", "n_head", "n_layer", "mlp", "steps",
                         "lr", "n_phrases", "feat_bins"):
                self.assertNotIn(gone, cfg, "%s leaked in %s" % (gone, name))

    def test_large_meets_measurement_bars(self) -> None:
        """Large lane: ≥50 STT clips, ≥20 roundtrip utterances."""
        cfg = resolve_scale("large")
        self.assertGreaterEqual(cfg["stt_clips"], 50)
        self.assertGreaterEqual(cfg["roundtrip_utts"], 20)

    def test_tiny_is_ci_smoke(self) -> None:
        """Tiny lane: Whisper tiny, small clip counts, CPU."""
        cfg = resolve_scale("tiny")
        self.assertEqual(cfg["stt_variant"], "tiny")
        self.assertLessEqual(cfg["stt_clips"], 16)
        self.assertFalse(cfg["prefer_gpu"])


class TestDeviceGuard(unittest.TestCase):
    """Never 6000; CPU always allowed."""

    def test_cpu_force(self) -> None:
        """Explicit cpu always works."""
        scale = resolve_scale("large")
        pick = pick_voice_device(scale=scale, force="cpu")
        self.assertEqual(pick["device"], "cpu")
        self.assertEqual(pick["never"], "rtx-pro-6000")

    def test_tiny_auto_ok(self) -> None:
        """Tiny auto never raises and stays off the 6000."""
        scale = resolve_scale("tiny")
        pick = pick_voice_device(scale=scale, force="auto")
        self.assertIn(pick["device"], ("cpu", "cuda"))
        self.assertEqual(pick["never"], "rtx-pro-6000")

    def test_bad_force(self) -> None:
        """Unknown device string raises."""
        with self.assertRaises(ValueError):
            pick_voice_device(scale=resolve_scale("tiny"), force="6000")


class TestFetchManifest(unittest.TestCase):
    """Fetch script manifest: pinned sha256 + sizes, models/ dests."""

    def test_entries_well_formed(self) -> None:
        """Every entry pins a 64-hex sha256 and a byte size."""
        self.assertGreaterEqual(len(fetch_models.FILES), 4)
        for entry in fetch_models.FILES:
            sha = str(entry["sha256"])
            self.assertEqual(len(sha), 64, sha)
            int(sha, 16)  # raises unless hex
            self.assertGreater(int(entry["size"]), 0)
            self.assertTrue(str(entry["url"]).startswith("https://"))
            dest = str(entry["dest"])
            self.assertIn("models/spark-voice-", dest)

    def test_covers_stt_and_tts(self) -> None:
        """Manifest covers both STT variants and the TTS model."""
        dests = [str(e["dest"]) for e in fetch_models.FILES]
        self.assertTrue(any("large-v3-turbo" in d for d in dests))
        self.assertTrue(any("/tiny/" in d for d in dests))
        self.assertTrue(any("kokoro" in d for d in dests))
        self.assertTrue(any("voices" in d for d in dests))


class TestLJSpeechLoader(unittest.TestCase):
    """metadata.csv parsing + deterministic held-out tail."""

    def _make_corpus(self, root: Path, n: int = 4) -> None:
        wavs = root / "wavs"
        wavs.mkdir(parents=True)
        lines = []
        for i in range(n):
            clip = "LJ%03d-%04d" % (i + 1, 1)
            _write_test_wav(wavs / ("%s.wav" % clip))
            lines.append("%s|raw %d|normalized text %d" % (clip, i, i))
        (root / "metadata.csv").write_text(
            "\n".join(lines) + "\n", encoding="utf-8"
        )

    def test_load_sorted_uses_normalized_column(self) -> None:
        """Loader returns id/wav/text sorted by id, normalized col."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._make_corpus(root)
            rows = eval_real.load_ljspeech(root)
            self.assertEqual(len(rows), 4)
            self.assertEqual(rows[0]["text"], "normalized text 0")
            self.assertTrue(rows[0]["wav"].is_file())
            ids = [r["id"] for r in rows]
            self.assertEqual(ids, sorted(ids))

    def test_missing_metadata_raises(self) -> None:
        """Clear error when the corpus is not extracted."""
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(FileNotFoundError):
                eval_real.load_ljspeech(Path(tmp))

    def test_held_out_tail(self) -> None:
        """Held-out subset is the sorted tail, exact size."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._make_corpus(root, n=6)
            rows = eval_real.load_ljspeech(root)
            sub = eval_real.held_out_subset(rows, 2)
            self.assertEqual([r["id"] for r in sub],
                             [r["id"] for r in rows][-2:])
            with self.assertRaises(ValueError):
                eval_real.held_out_subset(rows, 0)
            with self.assertRaises(ValueError):
                eval_real.held_out_subset(rows, 99)


class TestEnvAndCLI(unittest.TestCase):
    """Env check + CLI surface stay honest without weights."""

    def test_check_env(self) -> None:
        """Env probe returns ok without secrets."""
        info = check_env(dry=True)
        self.assertTrue(info["ok"])
        self.assertNotIn("api_key", str(info).lower())
        self.assertEqual(info["never"], "rtx-pro-6000")
        self.assertIn("stt_weights", info)
        self.assertIn("tts_weights", info)

    def test_run_easy_loud_skip_without_weights(self) -> None:
        """Missing weights → loud skipped_no_weights, never fake ok."""
        with mock.patch(
            "sparklang.voice_easy.pipeline.stt_weights_present",
            lambda variant="tiny": False,
        ), mock.patch(
            "sparklang.voice_easy.pipeline.tts_weights_present",
            lambda: False,
        ):
            with tempfile.TemporaryDirectory() as tmp:
                result = run_easy(
                    root=Path(tmp), scale="tiny", device="cpu", dry=True
                )
        self.assertEqual(result["status"], "skipped_no_weights")
        self.assertIn("fetch", result["hint"])
        self.assertIn("stt:tiny", result["missing"])

    def test_cli_env_and_status(self) -> None:
        """CLI env/status/train run and stay truthful."""
        sys.path.insert(0, str(ROOT / "tools" / "spark-voice"))
        import cli as voice_cli

        self.assertEqual(voice_cli.main(["env", "--dry"]), 0)
        self.assertEqual(voice_cli.main(["status"]), 0)
        self.assertEqual(voice_cli.main(["train"]), 0)


@unittest.skipUnless(
    stt_weights_present("tiny")
    and tts_weights_present()
    and _real_deps_present(),
    SKIP_MSG,
)
class TestRealWeightsIntegration(unittest.TestCase):
    """Integration: real Whisper tiny + Kokoro on this box."""

    def test_stt_eval_tiny_real_clips(self) -> None:
        """Whisper tiny transcribes 2 real LJSpeech clips, WER sane."""
        report = eval_real.run_stt_eval(
            n_clips=2, variant="tiny", device="cpu"
        )
        self.assertTrue(report["ok"])
        self.assertEqual(report["n_clips"], 2)
        self.assertGreaterEqual(report["wer"], 0.0)
        self.assertLess(report["wer"], 0.8)
        self.assertTrue(all(d["hyp"] for d in report["details"]))

    def test_roundtrip_tiny_real(self) -> None:
        """Kokoro → Whisper tiny roundtrip on 2 real transcripts."""
        with tempfile.TemporaryDirectory() as tmp:
            report = eval_real.run_roundtrip_eval(
                n_utts=2,
                stt_variant="tiny",
                device="cpu",
                out_dir=Path(tmp),
            )
            self.assertTrue(report["ok"])
            self.assertEqual(report["n_utts"], 2)
            self.assertLess(report["wer"], 0.5)
            for d in report["details"]:
                self.assertTrue(Path(d["tts_wav"]).is_file())
                self.assertGreater(d["tts_seconds"], 0.5)

    def test_transcribe_returns_segments(self) -> None:
        """transcribe_wav returns text + timed segments, offline."""
        from sparklang.voice_easy.stt_real import transcribe_wav

        rows = eval_real.held_out_subset(eval_real.load_ljspeech(), 1)
        result = transcribe_wav(rows[0]["wav"], variant="tiny")
        self.assertTrue(result["ok"])
        self.assertTrue(result["text"])
        self.assertTrue(result["segments"])
        self.assertTrue(result["offline"])
        self.assertEqual(stt_model_dir("tiny").name, "tiny")

    def test_fetch_check_passes_on_this_box(self) -> None:
        """Pinned fetch manifest verifies against fetched weights."""
        self.assertEqual(fetch_models.main.__module__, "fetch_models")
        bad = [e for e in fetch_models.FILES
               if not fetch_models._verify(e)]
        self.assertEqual(bad, [])


if __name__ == "__main__":
    unittest.main()
