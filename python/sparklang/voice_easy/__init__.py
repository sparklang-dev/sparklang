"""Voice easy train — owned STT/TTS heads (tiny + large scales).

Piece-of-cake path for training Spark voice-related weights we write
here. Not ElevenLabs/Kokoro. Never RTX PRO 6000. Does not beat Claude.
"""

from __future__ import annotations

from sparklang.voice_easy.pipeline import run_easy
from sparklang.voice_easy.scales import SCALES, resolve_scale

__all__ = [
    "SCALES",
    "resolve_scale",
    "run_easy",
]
