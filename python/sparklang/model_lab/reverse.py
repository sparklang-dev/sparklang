"""Reverse-engineer a local open HF checkpoint (config + index).

Reads published ``config.json`` and optional
``model.safetensors.index.json``. Never loads weight tensors.
Never fetches closed models. Not a foundation-model trainer.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def _load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def reverse_local(model_dir: str | Path) -> dict[str, Any]:
    root = Path(model_dir)
    cfg_path = root / "config.json" if root.is_dir() else root
    if cfg_path.name != "config.json":
        cfg_path = root / "config.json"
    if not cfg_path.is_file():
        raise FileNotFoundError(
            f"no config.json under {root} "
            "(local published files only)"
        )
    cfg = _load_json(cfg_path)
    arches = cfg.get("architectures") or []
    architecture = arches[0] if arches else cfg.get("model_type")
    tensors: list[str] = []
    index_path = cfg_path.parent / "model.safetensors.index.json"
    if index_path.is_file():
        idx = _load_json(index_path)
        wmap = idx.get("weight_map") or {}
        tensors = sorted(wmap.keys())
    return {
        "op": "reverse",
        "mode": "live",
        "target": str(cfg_path.parent),
        "architecture": architecture,
        "hidden_size": cfg.get("hidden_size"),
        "num_hidden_layers": cfg.get("num_hidden_layers"),
        "num_attention_heads": cfg.get("num_attention_heads"),
        "vocab_size": cfg.get("vocab_size"),
        "model_type": cfg.get("model_type"),
        "tensors": tensors,
        "source": str(cfg_path),
        "keep_special_training": True,
        "note": (
            "inspect local published config/index only — "
            "not closed weights, not a new foundation LLM"
        ),
    }
