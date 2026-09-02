#!/usr/bin/env python3
"""spark_pref_pack — preference pack + tiny CPU ranker (not LoRA).

Builds chosen/rejected pairs from chat JSONL and trains a small
scorer that prefers the teacher reply over alternatives.
Artifacts: pref_pack.json + ranker.pt + checkpoint.json.
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

METHOD = "spark_pref_pack"


class Ranker(nn.Module):
    """Embed user+reply; score with a linear head."""

    def __init__(self, vocab: int, dim: int = 32) -> None:
        super().__init__()
        self.emb = nn.Embedding(vocab, dim, padding_idx=0)
        self.score = nn.Linear(dim * 2, 1)

    def encode(self, ids: torch.Tensor) -> torch.Tensor:
        mask = (ids != 0).float().unsqueeze(-1)
        e = self.emb(ids) * mask
        denom = mask.sum(dim=1).clamp(min=1.0)
        return e.sum(dim=1) / denom

    def forward(
        self, user_ids: torch.Tensor, reply_ids: torch.Tensor
    ) -> torch.Tensor:
        u = self.encode(user_ids)
        r = self.encode(reply_ids)
        return self.score(torch.cat([u, r], dim=-1)).squeeze(-1)


def train_pref_pack(
    dataset: str,
    base: str,
    out_dir: str,
    job_id: str,
    *,
    steps: int = 200,
    lr: float = 0.05,
) -> dict[str, Any]:
    """Train preference ranker; write pref_pack.json + ranker.pt."""
    root = Path(out_dir)
    root.mkdir(parents=True, exist_ok=True)
    pairs = load_pairs(Path(dataset))
    replies = sorted({a for _, a in pairs})
    if len(replies) < 2:
        raise ValueError("pref_pack needs ≥2 distinct assistant replies")

    pack: list[dict[str, str]] = []
    for i, (u, chosen) in enumerate(pairs):
        rejected = replies[(i + 1) % len(replies)]
        if rejected == chosen:
            rejected = replies[(i + 2) % len(replies)]
        pack.append(
            {"user": u, "chosen": chosen, "rejected": rejected}
        )

    vocab: dict[str, int] = {"<pad>": 0, "<unk>": 1}
    for u, a in pairs:
        for w in tokenize(u) + tokenize(a):
            if w not in vocab:
                vocab[w] = len(vocab)

    def encode(text: str, width: int = 32) -> torch.Tensor:
        ids = [vocab.get(w, 1) for w in tokenize(text)][:width]
        ids += [0] * (width - len(ids))
        return torch.tensor(ids, dtype=torch.long)

    users = torch.stack([encode(p["user"]) for p in pack])
    chosen = torch.stack([encode(p["chosen"]) for p in pack])
    rejected = torch.stack([encode(p["rejected"]) for p in pack])

    model = Ranker(len(vocab))
    opt = torch.optim.Adam(model.parameters(), lr=lr)
    t0 = time.time()
    last_loss = 0.0
    model.train()
    for _ in range(steps):
        opt.zero_grad(set_to_none=True)
        s_pos = model(users, chosen)
        s_neg = model(users, rejected)
        # Softmax preference loss: prefer chosen over rejected.
        loss = -F.logsigmoid(s_pos - s_neg).mean()
        loss.backward()
        opt.step()
        last_loss = float(loss.item())

    pack_path = root / "pref_pack.json"
    ranker_path = root / "ranker.pt"
    ckpt_path = root / "checkpoint.json"
    marker_path = root / "ARTIFACT"

    pack_path.write_text(
        json.dumps({"method": METHOD, "pairs": pack}, indent=2) + "\n",
        encoding="utf-8",
    )
    torch.save(
        {
            "method": METHOD,
            "job_id": job_id,
            "vocab": vocab,
            "state_dict": {
                k: v.cpu() for k, v in model.state_dict().items()
            },
            "dim": 32,
        },
        ranker_path,
    )
    meta = {
        "method": METHOD,
        "job_id": job_id,
        "base": base,
        "dataset": dataset,
        "pairs": len(pack),
        "vocab_size": len(vocab),
        "steps": steps,
        "final_loss": round(last_loss, 6),
        "device": "cpu",
        "elapsed_s": round(time.time() - t0, 3),
        "pref_pack": str(pack_path),
        "ranker": str(ranker_path),
        "note": (
            "Spark method: preference pack + CPU ranker "
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
        str(ranker_path),
        final_loss=meta["final_loss"],
        pref_pack=str(pack_path),
    )
    return {
        "pref_pack": str(pack_path),
        "ranker": str(ranker_path),
        "weights": str(ranker_path),
        "checkpoint": str(ckpt_path),
        "marker": str(marker_path),
        "adapter": str(ranker_path),
        "meta": meta,
    }
