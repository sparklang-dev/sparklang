"""Tiny (CI) vs large (opt-in) voice-easy train configs.

Large ≠ production vendor TTS overnight. Owned dims/steps only.
"""

from __future__ import annotations

import os
from typing import Any

# Tiny = default CI / piece-of-cake demo (CPU-fast).
# Large = opt-in; prefers RTX 5090; never 6000; VRAM hint honest.
SCALES: dict[str, dict[str, Any]] = {
    "tiny": {
        "name": "tiny",
        "dim": 16,
        "n_head": 2,
        "n_layer": 1,
        "mlp": 64,
        "steps": 48,
        "lr": 0.35,
        "n_phrases": 6,
        "feat_bins": 8,
        "vram_gi_hint": 0.05,
        "prefer_gpu": False,
        "require_5090": False,
        "note": "CI / piece-of-cake demo",
    },
    "large": {
        "name": "large",
        "dim": 256,
        "n_head": 8,
        "n_layer": 4,
        "mlp": 1024,
        "steps": 80,
        "lr": 0.06,
        "n_phrases": 32,
        "feat_bins": 32,
        "vram_gi_hint": 2.0,
        "prefer_gpu": True,
        "require_5090": True,
        "note": (
            "Opt-in larger owned head — still not ElevenLabs; "
            "prefer 5090; never 6000"
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
    cfg["brain"] = "owned-weights"
    return cfg
