"""Voice-easy scales: tiny (CI smoke) vs large (real measurement).

Scales now mean **eval subset size + model variant**, nothing else:

- tiny  — Whisper ``tiny`` + Kokoro, 8-clip STT smoke, 4-utterance
  roundtrip. CPU-fast; the CI default.
- large — Whisper ``large-v3-turbo`` + Kokoro, ≥50-clip STT eval,
  ≥20-utterance roundtrip. The real measurement lane.

No owned toy heads, no fake dims. Weights are pretrained open
models fetched once (Whisper MIT / Kokoro Apache-2.0), then offline.
"""

from __future__ import annotations

import os
from typing import Any

SCALES: dict[str, dict[str, Any]] = {
    "tiny": {
        "name": "tiny",
        "stt_variant": "tiny",
        "stt_clips": 8,
        "roundtrip_utts": 4,
        "prefer_gpu": False,
        "require_5090": False,
        "vram_gi_hint": 0.5,
        "note": "CI smoke — Whisper tiny + Kokoro on CPU",
    },
    "large": {
        "name": "large",
        "stt_variant": "large-v3-turbo",
        "stt_clips": 50,
        "roundtrip_utts": 20,
        "prefer_gpu": True,
        "require_5090": False,
        "vram_gi_hint": 3.0,
        "note": (
            "Real measurement — Whisper large-v3-turbo + Kokoro; "
            "CPU int8 default, RTX 5090 optional (never 6000)"
        ),
    },
}


def resolve_scale(
    scale: str | None = None,
    *,
    env: dict[str, str] | None = None,
) -> dict[str, Any]:
    """Resolve scale from flag or VOICE_SCALE env (default tiny)."""
    envmap = env if env is not None else os.environ
    raw = (scale or envmap.get("VOICE_SCALE") or "tiny").strip().lower()
    if raw not in SCALES:
        raise ValueError(
            "scale must be tiny|large (got %r); "
            "set --scale or VOICE_SCALE" % raw
        )
    cfg = dict(SCALES[raw])
    cfg["never"] = "rtx-pro-6000"
    cfg["weights"] = "pretrained-open"
    return cfg
