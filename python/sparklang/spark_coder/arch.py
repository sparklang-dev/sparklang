"""Spark-coder architecture constants (written in this repo).

Tensor names match Spark factory safetensors (`emit_init_weights`)
so TRAIN/STEP artifacts stay compatible.

Scales:
- **tiny** — CI / default (dim 32, n_layer 2)
- **large** — opt-in (dim 64, n_layer 4; F-lane-aligned)

Prefer RTX 5090 for GPU SGD; never RTX PRO 6000. Does not beat Claude.
"""

from __future__ import annotations

from typing import Any

# Byte LM — UTF-8 bytes as tokens. Written here, not imported.
VOCAB = 256
DIM = 32
N_LAYER = 2
N_HEAD = 4
N_KV = 2
HEAD_DIM = DIM // N_HEAD
MLP = DIM * 4

PROFILE = "spark-coder"
NEVER_GPU = "rtx-pro-6000"
BEATS_CLAUDE = False

# Opt-in large (matches examples/fixtures/train/scale_config.json).
LARGE_DIM = 64
LARGE_N_LAYER = 4

SCALES = ("tiny", "large")


def _arch_body(
    *,
    dim: int,
    n_layer: int,
    scale: str,
    ci_default: bool,
) -> dict[str, Any]:
    """Build an arch dict for one named scale."""
    n_head = N_HEAD
    if dim % n_head != 0:
        raise ValueError(
            "dim %d must be divisible by n_head=%d" % (dim, n_head)
        )
    return {
        "profile": PROFILE,
        "scale": scale,
        "ci_default": ci_default,
        "vocab": VOCAB,
        "dim": int(dim),
        "n_layer": int(n_layer),
        "n_head": n_head,
        "n_kv": N_KV,
        "head_dim": int(dim) // n_head,
        "mlp": int(dim) * 4,
        "genome": "SPARK_BC",
        "factory": "Spark language",
        "beats_claude": BEATS_CLAUDE,
        "device": "cpu",
        "prefer_device": "rtx-5090",
        "never": NEVER_GPU,
        "brain": "owned-weights",
        "note": (
            "TinyCoder written+trained in sparklang; "
            "not a downloaded base model; scale=%s; "
            "not beat Claude; never 6000"
            % scale
        ),
    }


def scale_table() -> list[dict[str, Any]]:
    """Honesty rows: tiny (CI) vs large (opt-in)."""
    return [
        {
            "scale": "tiny",
            "ci_default": True,
            "dim": DIM,
            "n_layer": N_LAYER,
            "n_head": N_HEAD,
            "vocab": VOCAB,
            "approx_params": DIM * VOCAB * 2
            + N_LAYER * (4 * DIM * DIM + 3 * DIM * (DIM * 4)),
            "train": "make spark-coder-train",
            "cli": "./spark-code train --scale tiny",
            "device": "CPU default; RTX 5090 OK",
            "never": NEVER_GPU,
            "vram_note": (
                "CPU-fast CI fixture; 5090 optional, "
                "busy heuristic skips when >28 GiB used"
            ),
            "beats_claude": False,
        },
        {
            "scale": "large",
            "ci_default": False,
            "dim": LARGE_DIM,
            "n_layer": LARGE_N_LAYER,
            "n_head": N_HEAD,
            "vocab": VOCAB,
            "approx_params": LARGE_DIM * VOCAB * 2
            + LARGE_N_LAYER
            * (
                4 * LARGE_DIM * LARGE_DIM
                + 3 * LARGE_DIM * (LARGE_DIM * 4)
            ),
            "train": "make spark-coder-train-large",
            "cli": "./spark-code train --scale large",
            "device": "Prefer RTX 5090; CPU OK",
            "never": NEVER_GPU,
            "vram_note": (
                "Still small vs production LLMs; fits 5090. "
                "Hard-refuse RTX PRO 6000 (voice-only)."
            ),
            "beats_claude": False,
        },
    ]


def resolve_scale(scale: str | None = None) -> str:
    """Normalize scale name; default tiny."""
    name = (scale or "tiny").strip().lower()
    if name not in SCALES:
        raise ValueError(
            "scale must be tiny|large (got %r)" % scale
        )
    return name


def arch_for_scale(scale: str | None = None) -> dict[str, Any]:
    """Return arch for tiny (default) or large (opt-in)."""
    name = resolve_scale(scale)
    if name == "large":
        return _arch_body(
            dim=LARGE_DIM,
            n_layer=LARGE_N_LAYER,
            scale="large",
            ci_default=False,
        )
    return _arch_body(
        dim=DIM,
        n_layer=N_LAYER,
        scale="tiny",
        ci_default=True,
    )


def default_arch() -> dict[str, Any]:
    """Return the owned TinyCoder arch dict (tiny / CI default)."""
    return arch_for_scale("tiny")


def layer_prefix(li: int) -> str:
    """Tensor name prefix for layer li."""
    return "spark.layers.%d" % int(li)
