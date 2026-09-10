"""Real TTS (voice): Kokoro-82M via kokoro-onnx (Apache-2.0 weights).

Open weights only, fetched once into ``models/spark-voice-tts/`` by
``tools/spark-voice/fetch_models.py`` and then run fully offline on
CPU (ONNX Runtime). Produces real natural speech WAVs — no sine
tones, no file-size "gates".
"""

from __future__ import annotations

import array
import wave
from pathlib import Path
from typing import Any, Iterable

_REPO_ROOT = Path(__file__).resolve().parents[3]
TTS_MODELS_ROOT = _REPO_ROOT / "models" / "spark-voice-tts"
TTS_MODEL_ONNX = TTS_MODELS_ROOT / "kokoro-v1.0.onnx"
TTS_VOICES_BIN = TTS_MODELS_ROOT / "voices-v1.0.bin"

DEFAULT_VOICE = "af_heart"
KOKORO_SAMPLE_RATE = 24000

_kokoro_cache: dict[str, Any] = {}


class TTSWeightsMissingError(RuntimeError):
    """Raised when fetched TTS weights are not present on disk."""


def tts_weights_present() -> bool:
    """True when the Kokoro ONNX model + voices file are fetched."""
    return TTS_MODEL_ONNX.is_file() and TTS_VOICES_BIN.is_file()


def _load_kokoro() -> Any:
    """Load (cached) Kokoro session from local weights only."""
    if not tts_weights_present():
        raise TTSWeightsMissingError(
            "TTS weights missing — run: "
            "python3 tools/spark-voice/fetch_models.py"
        )
    if "kokoro" not in _kokoro_cache:
        from kokoro_onnx import Kokoro

        _kokoro_cache["kokoro"] = Kokoro(
            str(TTS_MODEL_ONNX), str(TTS_VOICES_BIN)
        )
    return _kokoro_cache["kokoro"]


def list_voices() -> list[str]:
    """Return available Kokoro voice ids from the local voices file."""
    kokoro = _load_kokoro()
    voices = getattr(kokoro, "voices", None)
    if voices is None:
        return []
    if isinstance(voices, dict):
        return sorted(voices.keys())
    return sorted(str(v) for v in voices)


def _write_wav(
    path: Path, samples: Iterable[float], rate: int
) -> None:
    """Write float [-1, 1] samples as mono S16_LE PCM WAV (stdlib)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm16 = array.array(
        "h",
        (
            int(max(-1.0, min(1.0, float(s))) * 32767.0)
            for s in samples
        ),
    )
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(int(rate))
        wf.writeframes(pcm16.tobytes())


def speak(
    text: str,
    out_wav: str | Path,
    *,
    voice: str = DEFAULT_VOICE,
    speed: float = 1.0,
    lang: str = "en-us",
) -> dict[str, Any]:
    """Synthesize text to a real speech WAV via Kokoro (offline).

    Returns dict with path, seconds, sample_rate, voice.
    """
    text = str(text).strip()
    if not text:
        raise ValueError("speak() needs non-empty text")
    out_wav = Path(out_wav)
    kokoro = _load_kokoro()
    samples, sample_rate = kokoro.create(
        text, voice=voice, speed=float(speed), lang=lang
    )
    # kokoro-onnx returns a numpy array; reshape(-1) flattens without
    # this module importing numpy (keeps CI unit tests numpy-free).
    flat = samples.reshape(-1)
    _write_wav(out_wav, flat, int(sample_rate))
    seconds = float(len(flat)) / float(sample_rate)
    return {
        "ok": True,
        "path": str(out_wav),
        "seconds": round(seconds, 3),
        "sample_rate": int(sample_rate),
        "voice": voice,
        "engine": "kokoro-onnx",
        "offline": True,
    }
