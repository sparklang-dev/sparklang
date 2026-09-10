"""Real STT (ears): faster-whisper / CTranslate2 Whisper wrapper.

Open weights only (Whisper, MIT license; CT2 repack by Systran /
Mobius Labs). Weights are fetched once into ``models/spark-voice-stt/``
by ``tools/spark-voice/fetch_models.py`` and then run fully offline —
this module forces ``HF_HUB_OFFLINE`` and only ever loads local
directories. CPU int8 is the default; CUDA is used only when the
caller explicitly opts in via the device guard (never the
RTX PRO 6000 — that GPU is voice-serving only).
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

# Hard offline: after fetch-once, no network in the wrapper path.
os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")

_REPO_ROOT = Path(__file__).resolve().parents[3]
STT_MODELS_ROOT = _REPO_ROOT / "models" / "spark-voice-stt"

# Whisper variants we support. "tiny" is the CI smoke fallback;
# "large-v3-turbo" is the real measurement lane.
STT_VARIANTS = ("tiny", "large-v3-turbo")
DEFAULT_VARIANT = "large-v3-turbo"

_model_cache: dict[tuple[str, str, str], Any] = {}


class WeightsMissingError(RuntimeError):
    """Raised when fetched STT weights are not present on disk."""


def stt_model_dir(variant: str = DEFAULT_VARIANT) -> Path:
    """Return the local dir for a Whisper variant (must exist)."""
    if variant not in STT_VARIANTS:
        raise ValueError(
            "stt variant must be one of %s (got %r)"
            % (list(STT_VARIANTS), variant)
        )
    return STT_MODELS_ROOT / variant


def stt_weights_present(variant: str = DEFAULT_VARIANT) -> bool:
    """True when the CT2 weights for variant are fetched locally."""
    d = stt_model_dir(variant)
    return (d / "model.bin").is_file() and (d / "config.json").is_file()


def _load_model(
    variant: str,
    *,
    device: str = "cpu",
    compute_type: str | None = None,
) -> Any:
    """Load (cached) WhisperModel from the local weights dir only."""
    if not stt_weights_present(variant):
        raise WeightsMissingError(
            "STT weights missing for %r — run: "
            "python3 tools/spark-voice/fetch_models.py" % variant
        )
    if compute_type is None:
        compute_type = "int8" if device == "cpu" else "float16"
    key = (variant, device, compute_type)
    if key not in _model_cache:
        from faster_whisper import WhisperModel

        _model_cache[key] = WhisperModel(
            str(stt_model_dir(variant)),
            device=device,
            compute_type=compute_type,
            local_files_only=True,
        )
    return _model_cache[key]


def transcribe_wav(
    path: str | Path,
    *,
    variant: str = DEFAULT_VARIANT,
    device: str = "cpu",
    language: str = "en",
) -> dict[str, Any]:
    """Transcribe a WAV file to text + segments with real Whisper.

    Returns dict with text, segments (start/end/text), language,
    and the variant/device actually used.
    """
    path = Path(path)
    if not path.is_file():
        raise FileNotFoundError("audio not found: %s" % path)
    model = _load_model(variant, device=device)
    segments_iter, info = model.transcribe(
        str(path),
        language=language,
        beam_size=5,
        vad_filter=True,
    )
    segments = [
        {
            "start": round(float(seg.start), 3),
            "end": round(float(seg.end), 3),
            "text": str(seg.text).strip(),
        }
        for seg in segments_iter
    ]
    text = " ".join(s["text"] for s in segments).strip()
    return {
        "ok": True,
        "text": text,
        "segments": segments,
        "language": str(getattr(info, "language", language)),
        "duration_s": round(float(getattr(info, "duration", 0.0)), 3),
        "variant": variant,
        "device": device,
        "offline": True,
    }
