"""Spark-coder architecture constants (written in this repo).

Tensor names match Spark factory safetensors (`emit_init_weights`)
so TRAIN/STEP artifacts stay compatible. Dims stay CPU-tiny.
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


def default_arch() -> dict[str, Any]:
    """Return the owned TinyCoder arch dict."""
    return {
        "profile": PROFILE,
        "vocab": VOCAB,
        "dim": DIM,
        "n_layer": N_LAYER,
        "n_head": N_HEAD,
        "n_kv": N_KV,
        "head_dim": HEAD_DIM,
        "mlp": MLP,
        "genome": "SPARK_BC",
        "factory": "Spark language",
        "beats_claude": BEATS_CLAUDE,
        "device": "cpu",
        "never": NEVER_GPU,
        "brain": "owned-weights",
        "note": (
            "TinyCoder written+trained in sparklang; "
            "not a downloaded base model"
        ),
    }


def layer_prefix(li: int) -> str:
    """Tensor name prefix for layer li."""
    return "spark.layers.%d" % int(li)
