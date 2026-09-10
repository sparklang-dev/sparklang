#!/usr/bin/env python3
"""Spark custom train: CPU distillation (not LoRA / not HF PEFT).

Teacher = assistant turns in chat JSONL. Student = tiny embedding +
linear head that picks the best reply class for a user message.

Forces torch CPU (no 5090/6000 hijack). Writes real weights.pt.
"""
from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any

# Keep CUDA off even if a GPU is visible on the host.
import os

os.environ["CUDA_VISIBLE_DEVICES"] = ""

import torch
from torch import nn
from torch.nn import functional as F

from common import load_pairs, tokenize, write_marker

METHOD = "spark_distill_cpu"


class Student(nn.Module):
    """Tiny bag-of-words embedder → reply-class logits."""

    def __init__(self, vocab: int, n_reply: int, dim: int = 32) -> None:
        super().__init__()
        self.emb = nn.Embedding(vocab, dim, padding_idx=0)
        self.head = nn.Linear(dim, n_reply)

    def forward(self, token_ids: torch.Tensor) -> torch.Tensor:
        # token_ids: (B, T)
        mask = (token_ids != 0).float().unsqueeze(-1)
        e = self.emb(token_ids) * mask
        denom = mask.sum(dim=1).clamp(min=1.0)
        pooled = e.sum(dim=1) / denom
        return self.head(pooled)


def train_distill(
    dataset: str,
    base: str,
    out_dir: str,
    job_id: str,
    *,
    steps: int = 200,
    lr: float = 0.05,
) -> dict[str, Any]:
    """Train student on CPU; write weights.pt + checkpoint.json."""
    root = Path(out_dir)
    root.mkdir(parents=True, exist_ok=True)
    pairs = load_pairs(Path(dataset))
    replies = sorted({a for _, a in pairs})
    reply_to_i = {r: i for i, r in enumerate(replies)}

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
        [reply_to_i[a] for _, a in pairs],
        dtype=torch.long,
    )

    device = torch.device("cpu")
    model = Student(len(vocab), len(replies)).to(device)
    opt = torch.optim.Adam(model.parameters(), lr=lr)
    t0 = time.time()
    last_loss = 0.0
    model.train()
    for step in range(1, steps + 1):
        opt.zero_grad(set_to_none=True)
        logits = model(xs.to(device))
        loss = F.cross_entropy(logits, ys.to(device))
        loss.backward()
        opt.step()
        last_loss = float(loss.item())

    weights_path = root / "weights.pt"
    ckpt_path = root / "checkpoint.json"
    marker_path = root / "ARTIFACT"
    payload = {
        "method": METHOD,
        "job_id": job_id,
        "base": base,
        "dataset": dataset,
        "vocab": vocab,
        "replies": replies,
        "state_dict": {k: v.cpu() for k, v in model.state_dict().items()},
        "dim": 32,
    }
    torch.save(payload, weights_path)

    meta = {
        "method": METHOD,
        "job_id": job_id,
        "base": base,
        "dataset": dataset,
        "pairs": len(pairs),
        "vocab_size": len(vocab),
        "n_replies": len(replies),
        "steps": steps,
        "final_loss": round(last_loss, 6),
        "device": "cpu",
        "elapsed_s": round(time.time() - t0, 3),
        "weights": str(weights_path),
        "note": (
            "Spark custom path: CPU distill student "
            "(not LoRA, not HF PEFT, no GPU)"
        ),
    }
    ckpt_path.write_text(
        json.dumps(meta, indent=2) + "\n",
        encoding="utf-8",
    )
    marker_path.write_text(
        f"{METHOD} {job_id}\n"
        f"weights={weights_path}\n"
        f"final_loss={meta['final_loss']}\n",
        encoding="utf-8",
    )
    return {
        "weights": str(weights_path),
        "checkpoint": str(ckpt_path),
        "marker": str(marker_path),
        # Contract alias: historical "adapter" key → real weights path.
        "adapter": str(weights_path),
        "meta": meta,
    }


def main() -> None:
    """CLI: distill one dataset into out/."""
    import argparse

    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dataset", required=True)
    ap.add_argument("--base", default="fixture-base")
    ap.add_argument("--out", required=True)
    ap.add_argument("--job-id", default="job-local")
    ap.add_argument("--steps", type=int, default=200)
    args = ap.parse_args()
    arts = train_distill(
        args.dataset,
        args.base,
        args.out,
        args.job_id,
        steps=args.steps,
    )
    print(json.dumps({"ok": True, "artifacts": {
        k: v for k, v in arts.items() if k != "meta"
    }, "meta": arts["meta"]}, indent=2))


if __name__ == "__main__":
    main()
