"""Train an abstain head on labeled hidden features (CPU)."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Optional, Union

os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")

import torch
from torch import nn

from sparklang.abstain.corpus import (
    SOURCE_BAG_HASH,
    SOURCE_HF,
    SOURCE_SYNTHETIC,
    SOURCE_TOY,
    load_corpus,
)
from sparklang.abstain.head import AbstainHead, save_head

PathLike = Union[str, Path]


def _hash_feats(text: str, dim: int) -> list[float]:
    """Deterministic bag hash — CI path without a real LM."""
    v = [0.0] * dim
    for tok in text.lower().split():
        h = hash(tok) % dim
        v[h] += 1.0
    n = sum(abs(x) for x in v) or 1.0
    return [x / n for x in v]


def _load_rows(dataset: Path) -> list[dict[str, Any]]:
    """JSONL rows: hidden|[float]|features + label 0/1."""
    raw_rows = load_corpus(dataset)
    rows: list[dict[str, Any]] = []
    feature_source = "unknown"
    for row in raw_rows:
        feats = row.get("hidden")
        src = str(row.get("source") or "")
        if feats is None:
            # Bag-of-hashes stub — legacy text-only fixtures.
            dim = int(row.get("dim") or 64)
            feats = _hash_feats(str(row["text"]), dim)
            src = SOURCE_BAG_HASH
        if feature_source == "unknown":
            feature_source = src or SOURCE_BAG_HASH
        rows.append(
            {
                "features": [float(x) for x in feats],
                "label": int(row["label"]),
                "source": src or feature_source,
            }
        )
    if not rows:
        raise ValueError(f"empty dataset: {dataset}")
    return rows


def _quality_for_source(source: str) -> str:
    """Honest quality stamp — never claim production accuracy."""
    if source in (SOURCE_HF, "hf_prefill"):
        return "hf_exported_unverified"
    if source == SOURCE_SYNTHETIC:
        return "synthetic_backbone_dim_match"
    if source in (SOURCE_TOY, "toy_stub"):
        return "toy_backbone"
    if source == SOURCE_BAG_HASH:
        return "bag_hash_fixture"
    return "fixture_unverified"


def train_abstain_head(
    dataset: PathLike,
    out: PathLike,
    *,
    kind: str = "internal",
    hidden_dim: Optional[int] = None,
    steps: int = 200,
    lr: float = 0.05,
    mlp: bool = False,
    seed: int = 0,
) -> dict[str, Any]:
    """Fit linear/MLP head; write real ``.pt`` weights."""
    rows = _load_rows(Path(dataset))
    dim = hidden_dim or len(rows[0]["features"])
    sources = sorted({str(r.get("source") or "") for r in rows})
    feature_source = sources[0] if len(sources) == 1 else "mixed"
    for r in rows:
        if len(r["features"]) != dim:
            raise ValueError(
                f"feature dim mismatch: want {dim} "
                f"got {len(r['features'])}"
            )
    quality = _quality_for_source(feature_source)
    torch.manual_seed(seed)
    head = AbstainHead(dim, mlp=mlp)
    opt = torch.optim.Adam(head.parameters(), lr=lr)
    loss_fn = nn.BCEWithLogitsLoss()
    x = torch.tensor(
        [r["features"] for r in rows], dtype=torch.float32
    )
    y = torch.tensor(
        [[float(r["label"])] for r in rows], dtype=torch.float32
    )
    head.train()
    last_loss = 0.0
    for _ in range(steps):
        opt.zero_grad()
        logits = head(x).unsqueeze(-1)
        loss = loss_fn(logits, y)
        loss.backward()
        opt.step()
        last_loss = float(loss.item())
    path = save_head(
        head,
        out,
        kind=kind,
        extra={
            "dataset": str(dataset),
            "steps": steps,
            "loss": last_loss,
            "n": len(rows),
            "feature_source": feature_source,
            "quality": quality,
            "note": (
                "not production accuracy — match target "
                "backbone hidden_dim before gate claims"
            ),
        },
    )
    return {
        "op": "head_train",
        "kind": kind,
        "out": str(path),
        "hidden_dim": dim,
        "steps": steps,
        "loss": last_loss,
        "n": len(rows),
        "feature_source": feature_source,
        "quality": quality,
        "note": (
            "not production accuracy — retrain on "
            "target-backbone hiddens before claims"
        ),
        "state": "succeeded",
    }
