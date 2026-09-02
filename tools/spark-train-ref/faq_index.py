#!/usr/bin/env python3
"""spark_faq_index — FAQ retrieval index + tiny CPU encoder (not LoRA).

Builds a FAQ corpus from chat JSONL (user question → assistant answer)
and trains a small dual-encoder that ranks the matching FAQ for each
query. Distinct from distill (reply class), pref (chosen/rejected), and
playbook (intent→template).
Artifacts: faq_index.json + encoder.pt + checkpoint.json.
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

METHOD = "spark_faq_index"


class Encoder(nn.Module):
    """Bag-of-words embedder → fixed vector for query or FAQ title."""

    def __init__(self, vocab: int, dim: int = 32) -> None:
        super().__init__()
        self.emb = nn.Embedding(vocab, dim, padding_idx=0)
        self.proj = nn.Linear(dim, dim)

    def forward(self, token_ids: torch.Tensor) -> torch.Tensor:
        mask = (token_ids != 0).float().unsqueeze(-1)
        e = self.emb(token_ids) * mask
        denom = mask.sum(dim=1).clamp(min=1.0)
        pooled = e.sum(dim=1) / denom
        return F.normalize(self.proj(pooled), dim=-1)


def train_faq_index(
    dataset: str,
    base: str,
    out_dir: str,
    job_id: str,
    *,
    steps: int = 200,
    lr: float = 0.05,
) -> dict[str, Any]:
    """Fit FAQ retriever; write faq_index.json + encoder.pt."""
    root = Path(out_dir)
    root.mkdir(parents=True, exist_ok=True)
    pairs = load_pairs(Path(dataset))

    by_answer: dict[str, list[str]] = {}
    for u, a in pairs:
        by_answer.setdefault(a, []).append(u)

    faqs: list[dict[str, Any]] = []
    for i, (answer, questions) in enumerate(sorted(by_answer.items())):
        title = questions[0]
        faqs.append(
            {
                "id": f"faq_{i:02d}",
                "title": title,
                "answer": answer,
                "aliases": questions,
            }
        )
    if len(faqs) < 2:
        raise ValueError("faq_index needs ≥2 distinct assistant answers")

    q_texts: list[str] = []
    labels: list[int] = []
    answer_to_i = {f["answer"]: i for i, f in enumerate(faqs)}
    for u, a in pairs:
        q_texts.append(u)
        labels.append(answer_to_i[a])

    vocab: dict[str, int] = {"<pad>": 0, "<unk>": 1}
    for text in q_texts + [f["title"] for f in faqs] + [
        f["answer"] for f in faqs
    ]:
        for w in tokenize(text):
            if w not in vocab:
                vocab[w] = len(vocab)

    def encode(text: str, width: int = 32) -> torch.Tensor:
        ids = [vocab.get(w, 1) for w in tokenize(text)][:width]
        ids += [0] * (width - len(ids))
        return torch.tensor(ids, dtype=torch.long)

    queries = torch.stack([encode(t) for t in q_texts])
    bank = torch.stack([encode(f["title"]) for f in faqs])
    ys = torch.tensor(labels, dtype=torch.long)

    model = Encoder(len(vocab))
    opt = torch.optim.Adam(model.parameters(), lr=lr)
    t0 = time.time()
    last_loss = 0.0
    model.train()
    for _ in range(steps):
        opt.zero_grad(set_to_none=True)
        q = model(queries)
        d = model(bank)
        logits = q @ d.T
        loss = F.cross_entropy(logits, ys)
        loss.backward()
        opt.step()
        last_loss = float(loss.item())

    index_path = root / "faq_index.json"
    encoder_path = root / "encoder.pt"
    ckpt_path = root / "checkpoint.json"
    marker_path = root / "ARTIFACT"

    index_path.write_text(
        json.dumps(
            {
                "method": METHOD,
                "faqs": faqs,
                "n_faqs": len(faqs),
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    torch.save(
        {
            "method": METHOD,
            "job_id": job_id,
            "vocab": vocab,
            "faq_ids": [f["id"] for f in faqs],
            "state_dict": {
                k: v.cpu() for k, v in model.state_dict().items()
            },
            "dim": 32,
        },
        encoder_path,
    )
    meta = {
        "method": METHOD,
        "job_id": job_id,
        "base": base,
        "dataset": dataset,
        "pairs": len(pairs),
        "n_faqs": len(faqs),
        "vocab_size": len(vocab),
        "steps": steps,
        "final_loss": round(last_loss, 6),
        "device": "cpu",
        "elapsed_s": round(time.time() - t0, 3),
        "faq_index": str(index_path),
        "encoder": str(encoder_path),
        "note": (
            "Spark method: FAQ index + CPU dual-encoder "
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
        str(encoder_path),
        final_loss=meta["final_loss"],
        faq_index=str(index_path),
    )
    return {
        "faq_index": str(index_path),
        "encoder": str(encoder_path),
        "weights": str(encoder_path),
        "checkpoint": str(ckpt_path),
        "marker": str(marker_path),
        "adapter": str(encoder_path),
        "meta": meta,
    }
