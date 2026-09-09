"""Eyes / vision — thin planned interface (not wired to the VM).

Spark tip has no vision encoder and no ``look`` language opcode.
This module documents the intended contract so docs and tests stay
honest without inventing a vision stack.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from pathlib import Path
class VisionStatus(str, Enum):
    """Lifecycle for the vision sense."""

    PLANNED = "planned"
    DRY_STUB = "dry_stub"
    LIVE = "live"


@dataclass(frozen=True)
class VisionRequest:
    """Image-in request for a future ``look`` language op."""

    path: Path
    prompt: str = ""
    dry_run: bool = True


@dataclass(frozen=True)
class VisionResult:
    """Result envelope — always honest about wiring status."""

    status: VisionStatus
    caption: str
    path: Path
    detail: str


def look(req: VisionRequest) -> VisionResult:
    """Return a planned/dry envelope; never invent image understanding.

    Live vision inference is **not** implemented. Callers must not
    treat ``caption`` as model output from Spark weights.
    """
    path = Path(req.path)
    if req.dry_run or not path.is_file():
        return VisionResult(
            status=VisionStatus.PLANNED,
            caption="",
            path=path,
            detail=(
                "eyes/vision not in Spark runtime — "
                "see docs/MODEL_ASPECTS.md"
            ),
        )
    # File exists but runtime still has no encoder.
    return VisionResult(
        status=VisionStatus.PLANNED,
        caption="",
        path=path,
        detail=(
            "image path present; vision encoder / look opcode "
            "not shipped"
        ),
    )


def sense_name() -> str:
    """Stable sense label for docs and tests."""
    return "eyes"


def default_status() -> VisionStatus:
    """Tip status for the eyes sense."""
    return VisionStatus.PLANNED
