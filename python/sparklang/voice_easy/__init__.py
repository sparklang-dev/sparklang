"""Voice easy — real STT/TTS on pretrained open weights, offline.

STT (ears): Whisper via faster-whisper / CTranslate2 (MIT weights).
TTS (voice): Kokoro-82M via kokoro-onnx (Apache-2.0 weights).
Weights fetch once into ``models/`` (gitignored), then every path
runs offline. CPU int8 default; RTX 5090 optional; the RTX PRO 6000
is voice-serving only and never used here.
"""

from __future__ import annotations

from sparklang.voice_easy.pipeline import run_easy
from sparklang.voice_easy.scales import SCALES, resolve_scale

__all__ = [
    "SCALES",
    "resolve_scale",
    "run_easy",
]
