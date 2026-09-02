"""Export last-token hiddens for abstain head train (CPU).

Dim-matched JSONL for ``head train``. Prefer a real HF backbone when
``model`` is set. Without HF / model, a seeded **toy backbone** stands
in for CI — same dim contract, not a production LoRA or real LM.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, Optional, Union

os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")

import torch

from sparklang.abstain.generate import (
    require_explicit_model,
    try_hf_last_hidden,
)
from sparklang.abstain.train import _hash_feats

PathLike = Union[str, Path]


def toy_backbone_hidden(
    text: str,
    dim: int,
    *,
    seed: int = 42,
) -> list[float]:
    """Deterministic dim-D vector — CI stand-in for LM export.

    Not a real backbone. Use only when documenting the export→train
    pipeline offline / without downloading weights.
    """
    if dim < 1:
        raise ValueError(f"dim must be >= 1, got {dim}")
    # Bag-hash into dim, then rotate with a seeded sign pattern so
    # vectors are dense-ish and match a fixed width like a real head.
    bag = _hash_feats(text, dim)
    g = torch.Generator()
    g.manual_seed(int(seed) + dim)
    signs = torch.randint(
        0, 2, (dim,), generator=g, dtype=torch.int64
    )
    signs = signs.mul(2).sub(1).to(torch.float32)
    v = torch.tensor(bag, dtype=torch.float32) * signs
    n = float(torch.linalg.vector_norm(v).item()) or 1.0
    return (v / n).tolist()


def _row_text_label(row: dict[str, Any]) -> tuple[str, int]:
    """Pull text + 0/1 label from a JSONL row."""
    text = row.get("text") or row.get("prompt")
    if text is None:
        raise ValueError(f"row needs text/prompt: {row!r}")
    label = row.get("label")
    if label is None:
        label = row.get("abstain")
    if label is None:
        raise ValueError(f"row needs label/abstain: {row!r}")
    return str(text), int(label)


def export_hiddens(
    dataset: PathLike,
    out: PathLike,
    *,
    model: Optional[str] = None,
    hidden_dim: Optional[int] = None,
    seed: int = 42,
    kind: str = "internal",
) -> dict[str, Any]:
    """Write JSONL rows with ``hidden`` + ``label`` (+ text).

    * ``model`` set → HF last-token hidden (refuses gateway aliases).
      ``hidden_dim`` must match the model width or be omitted.
    * ``model`` unset → toy backbone at ``hidden_dim`` (default 16).
    """
    ds = Path(dataset)
    out_p = Path(out)
    out_p.parent.mkdir(parents=True, exist_ok=True)
    rows_in: list[dict[str, Any]] = []
    for line in ds.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        rows_in.append(json.loads(line))
    if not rows_in:
        raise ValueError(f"empty dataset: {ds}")

    source = "toy"
    dim: Optional[int] = hidden_dim
    model_id: Optional[str] = None
    if model:
        model_id = require_explicit_model(model)
        source = "hf"

    exported: list[dict[str, Any]] = []
    for row in rows_in:
        text, label = _row_text_label(row)
        if source == "hf":
            assert model_id is not None
            tens = try_hf_last_hidden(model_id, text)
            if tens is None:
                raise SystemExit(
                    "export: HF hidden unavailable "
                    f"(model={model_id!r}; install "
                    "python/[hf] + weights, or omit --model "
                    "for toy backbone)"
                )
            feats = tens.tolist()
            if dim is None:
                dim = len(feats)
            elif len(feats) != dim:
                raise ValueError(
                    f"hidden_dim mismatch: want {dim} "
                    f"got {len(feats)} for {text!r}"
                )
        else:
            if dim is None:
                dim = 16
            feats = toy_backbone_hidden(
                text, dim, seed=seed
            )
        exported.append(
            {
                "text": text,
                "label": label,
                "hidden": feats,
                "dim": dim,
                "source": source,
                "kind": kind,
            }
        )

    assert dim is not None
    with out_p.open("w", encoding="utf-8") as fh:
        for r in exported:
            fh.write(json.dumps(r, separators=(",", ":")) + "\n")

    return {
        "op": "head_export",
        "dataset": str(ds),
        "out": str(out_p),
        "n": len(exported),
        "hidden_dim": dim,
        "source": source,
        "model": model_id or "",
        "kind": kind,
        "state": "succeeded",
    }
