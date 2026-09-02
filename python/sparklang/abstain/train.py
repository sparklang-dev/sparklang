"""Train an abstain head on labeled hidden features (CPU)."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, Optional, Union

os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")

import torch
from torch import nn

from sparklang.abstain.head import AbstainHead, save_head

PathLike = Union[str, Path]


def _load_rows(dataset: Path) -> list[dict[str, Any]]:
    """JSONL rows: hidden|[float]|features + label 0/1."""
    rows: list[dict[str, Any]] = []
    for line in dataset.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        row = json.loads(line)
        label = row.get("label")
        if label is None:
            label = row.get("abstain")
        feats = row.get("hidden") or row.get("features")
        if feats is None and "text" in row:
            # Bag-of-hashes stub features for text-only fixtures.
            feats = _hash_feats(str(row["text"]), int(row.get("dim") or 64))
        if feats is None or label is None:
            raise ValueError(
                f"row needs hidden/features + label: {row!r}"
            )
        rows.append({"features": [float(x) for x in feats], "label": int(label)})
    if not rows:
        raise ValueError(f"empty dataset: {dataset}")
    return rows


def _hash_feats(text: str, dim: int) -> list[float]:
    """Deterministic bag hash — CI path without a real LM."""
    v = [0.0] * dim
    for tok in text.lower().split():
        h = hash(tok) % dim
        v[h] += 1.0
    n = sum(abs(x) for x in v) or 1.0
    return [x / n for x in v]


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
    for r in rows:
        if len(r["features"]) != dim:
            raise ValueError(
                f"feature dim mismatch: want {dim} "
                f"got {len(r['features'])}"
            )
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
        "state": "succeeded",
    }
