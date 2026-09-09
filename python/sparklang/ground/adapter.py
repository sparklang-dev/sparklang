"""Thin owned adapter API for external bases (e.g. Qwen) + Spark.

Mirrors language ``model modify keep_existing``: attach-only.
Full Qwen SFT remains opt-in large on **5090** (never **6000**).
This module writes manifests — it does not download Hub weights
or run PEFT train.
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Optional


@dataclass
class AdapterSpec:
    """Attach plan for one adapter or abstain head."""

    path: str
    kind: str = "adapter"  # adapter | head | reply_pack
    note: str = ""


def device_policy() -> dict[str, Any]:
    """Standing GPU policy for adaptation jobs."""
    return {
        "prefer": "5090",
        "never": "6000",
        "cpu_ok": True,
        "honesty": (
            "Full external-base SFT (e.g. Qwen) is opt-in large "
            "on 5090; Spark attach API does not route train to "
            "the RTX PRO 6000 (voice-only)."
        ),
    }


def attach_adapter_manifest(
    *,
    base: str,
    keep_existing: str,
    add: list[AdapterSpec] | list[dict[str, Any]],
    out: str | Path,
    base_kind: str = "external",
    heads: Optional[list[str]] = None,
) -> dict[str, Any]:
    """Write an attach-only modify manifest (keep special training).

    ``base`` may be a local HF dir name (e.g. ``qwen3``) or Spark
    owned id (``spark-coder``). Never deletes existing LoRA / heads.
    """
    specs: list[dict[str, Any]] = []
    for item in add:
        if isinstance(item, AdapterSpec):
            specs.append(asdict(item))
        else:
            specs.append(dict(item))
    payload: dict[str, Any] = {
        "op": "adapter_attach",
        "mode": "attach_only",
        "base": base,
        "base_kind": base_kind,
        "keep_existing": keep_existing,
        "keep_special_training": True,
        "adapters": specs,
        "heads": list(heads or []),
        "device_policy": device_policy(),
        "functions": [
            "expect",
            "retrieve",
            "abstain",
            "verify",
            "cite",
        ],
        "note": (
            "Thin Spark adapter API — attach LoRA-style / abstain "
            "hooks. Recompile ≠ semantics. Full Qwen SFT is "
            "operator opt-in on 5090, never 6000. Does not beat "
            "Claude."
        ),
    }
    out_path = Path(out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(
        json.dumps(payload, indent=2) + "\n",
        encoding="utf-8",
    )
    payload["manifest"] = str(out_path)
    return payload
