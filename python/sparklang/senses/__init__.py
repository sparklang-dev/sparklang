"""Spark multimodal sense interfaces (ears/eyes/speaking stubs).

Ears/speaking live in the language VM + ``tools/voice/``. Eyes are
documented here as **planned** only — no runtime opcode on tip.
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
]
