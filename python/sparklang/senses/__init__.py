"""Spark multimodal sense interfaces (ears/eyes/speaking stubs).

Ears/speaking live in the language VM + ``tools/voice/``. Training
happy path: ``./spark-voice easy`` (see ``sparklang.voice_easy``).
Eyes are documented here as **planned** only — no runtime opcode on tip.
"""

from .vision import (
    VisionRequest,
    VisionResult,
    VisionStatus,
    look,
)

__all__ = [
    "VisionRequest",
    "VisionResult",
    "VisionStatus",
    "look",
    "voice_train_hint",
]


def voice_train_hint() -> dict[str, str]:
    """Point engineers at the voice-easy train path (L-lane)."""
    return {
        "ears": "listen / ./spark-stt-tts",
        "speaking": "speak / ./spark-stt-tts",
        "train": "./spark-voice easy --dry",
        "large": "./spark-voice easy --scale large --device auto",
        "docs": "docs/VOICE_EASY.md",
        "never": "rtx-pro-6000",
        "beats_claude": "false",
    }
