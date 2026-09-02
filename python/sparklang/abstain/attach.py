"""Attach abstain head weights to a local model directory."""

from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Any, Union

PathLike = Union[str, Path]


def attach_head(
    model: PathLike,
    weights: PathLike,
    out: PathLike,
    *,
    kind: str = "internal",
    threshold: float = 0.7,
    idk: str = "I don't know.",
) -> dict[str, Any]:
    """Copy head beside model and write a SparkLang manifest.

    Does **not** mutate backbone weights. Does **not** invent LoRA.
    """
    model_p = Path(model)
    weights_p = Path(weights)
    out_p = Path(out)
    if not weights_p.is_file():
        raise FileNotFoundError(f"weights missing: {weights_p}")
    out_p.parent.mkdir(parents=True, exist_ok=True)
    dest_weights = out_p.parent / weights_p.name
    if weights_p.resolve() != dest_weights.resolve():
        shutil.copy2(weights_p, dest_weights)
    meta_src = weights_p.with_suffix(".meta.json")
    meta: dict[str, Any] = {}
    if meta_src.is_file():
        meta = json.loads(meta_src.read_text(encoding="utf-8"))
    manifest = {
        "spark": "abstain_attach",
        "version": 1,
        "kind": kind,
        "model": str(model_p),
        "weights": str(dest_weights),
        "threshold": float(threshold),
        "idk": idk,
        "head_meta": meta,
        "note": (
            "Frozen backbone + abstain probe only; "
            "not a full fine-tune / not LoRA"
        ),
    }
    out_p.write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    # Convenience pointer inside model dir when it exists on disk.
    if model_p.is_dir():
        ptr = model_p / "spark_abstain_manifest.json"
        ptr.write_text(
            json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
        )
        manifest["model_ptr"] = str(ptr)
    return {
        "op": "head_attach",
        "kind": kind,
        "manifest": str(out_p),
        "weights": str(dest_weights),
        "model": str(model_p),
        "state": "succeeded",
    }


def load_manifest(path: PathLike) -> dict[str, Any]:
    """Load an attach manifest JSON."""
    return json.loads(Path(path).read_text(encoding="utf-8"))
