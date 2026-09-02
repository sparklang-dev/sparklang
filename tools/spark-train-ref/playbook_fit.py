#!/usr/bin/env python3
"""spark_playbook_fit — intent→playbook router on CPU (not LoRA).

Clusters teacher replies into playbook templates and trains a tiny
classifier from user text → playbook id.
Artifacts: playbooks.json + router.pt + checkpoint.json.
"""
from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any

import torch
from torch import nn
from torch.nn import functional as F

from common import load_pairs, tokenize, write_marker

METHOD = "spark_playbook_fit"


class Router(nn.Module):
    """Bag-of-words embedder → playbook logits."""

    def __init__(self, vocab: int, n_pb: int, dim: int = 32) -> None:
        super().__init__()
        self.emb = nn.Embedding(vocab, dim, padding_idx=0)
        self.head = nn.Linear(dim, n_pb)

    def forward(self, token_ids: torch.Tensor) -> torch.Tensor:
        mask = (token_ids != 0).float().unsqueeze(-1)
        e = self.emb(token_ids) * mask
        denom = mask.sum(dim=1).clamp(min=1.0)
        pooled = e.sum(dim=1) / denom
        return self.head(pooled)


def train_playbook_fit(
    dataset: str,
    base: str,
    out_dir: str,
    job_id: str,
    *,
    steps: int = 200,
    lr: float = 0.05,
) -> dict[str, Any]:
    """Fit playbook router; write playbooks.json + router.pt."""
    root = Path(out_dir)
    root.mkdir(parents=True, exist_ok=True)
    pairs = load_pairs(Path(dataset))
    # One playbook per distinct assistant reply (template = reply).
    templates = sorted({a for _, a in pairs})
    pb_ids = {t: f"pb_{i:02d}" for i, t in enumerate(templates)}
    playbooks = [
        {
            "id": pb_ids[t],
            "title": f"reply:{t[:40]}",
            "template": t,
            "steps": ["match_intent", "emit_template"],
        }
        for t in templates
    ]
    label = {t: i for i, t in enumerate(templates)}

    vocab: dict[str, int] = {"<pad>": 0, "<unk>": 1}
    for u, _ in pairs:
        for w in tokenize(u):
            if w not in vocab:
                vocab[w] = len(vocab)

    def encode(text: str, width: int = 32) -> torch.Tensor:
        ids = [vocab.get(w, 1) for w in tokenize(text)][:width]
        ids += [0] * (width - len(ids))
        return torch.tensor(ids, dtype=torch.long)

    xs = torch.stack([encode(u) for u, _ in pairs])
    ys = torch.tensor(
        [label[a] for _, a in pairs], dtype=torch.long
    )

    model = Router(len(vocab), len(templates))
    opt = torch.optim.Adam(model.parameters(), lr=lr)
    t0 = time.time()
    last_loss = 0.0
    model.train()
    for _ in range(steps):
        opt.zero_grad(set_to_none=True)
        logits = model(xs)
        loss = F.cross_entropy(logits, ys)
        loss.backward()
        opt.step()
        last_loss = float(loss.item())

    pb_path = root / "playbooks.json"
    router_path = root / "router.pt"
    ckpt_path = root / "checkpoint.json"
    marker_path = root / "ARTIFACT"

    pb_path.write_text(
        json.dumps(
            {"method": METHOD, "playbooks": playbooks}, indent=2
        )
        + "\n",
        encoding="utf-8",
    )
    torch.save(
        {
            "method": METHOD,
            "job_id": job_id,
            "vocab": vocab,
            "playbook_ids": [pb_ids[t] for t in templates],
            "state_dict": {
                k: v.cpu() for k, v in model.state_dict().items()
            },
            "dim": 32,
        },
        router_path,
    )
    meta = {
        "method": METHOD,
        "job_id": job_id,
        "base": base,
        "dataset": dataset,
        "pairs": len(pairs),
        "n_playbooks": len(playbooks),
        "vocab_size": len(vocab),
        "steps": steps,
        "final_loss": round(last_loss, 6),
        "device": "cpu",
        "elapsed_s": round(time.time() - t0, 3),
        "playbooks": str(pb_path),
        "router": str(router_path),
        "note": (
            "Spark method: playbook fit router on CPU "
            "(not LoRA, not HF PEFT)"
        ),
    }
    ckpt_path.write_text(
        json.dumps(meta, indent=2) + "\n", encoding="utf-8"
    )
    write_marker(
        marker_path,
        METHOD,
        job_id,
        str(router_path),
        final_loss=meta["final_loss"],
        playbooks=str(pb_path),
    )
    return {
        "playbooks": str(pb_path),
        "router": str(router_path),
        "weights": str(router_path),
        "checkpoint": str(ckpt_path),
        "marker": str(marker_path),
        "adapter": str(router_path),
        "meta": meta,
    }
