#!/usr/bin/env python3
"""spark_reply_pack — voice+text reply overlay on CPU (not LoRA).

Trains a tiny intent→reply router plus a reply pack that can overlay
**text and spoken scripts** onto a base that has **no voice** (or
lock major behaviors). Inventable facts require a SoT file — the
trainer fails loud otherwise. Never fabricates.
Artifacts: replies.json + gate.json + router.pt + checkpoint.json.
"""
from __future__ import annotations

import json
import re
import time
from pathlib import Path
from typing import Any

import torch
from torch import nn
from torch.nn import functional as F

from common import tokenize, write_marker

METHOD = "spark_reply_pack"
_PRICE = re.compile(r"\$\s*\d|\d+\.\d{2}")
_PHONE = re.compile(r"\b\d{3}[-.\s]?\d{3}[-.\s]?\d{4}\b")
_INVENTABLE = (
    "mayor of",
    "who is the current",
    "price at",
    "dryer start",
    "card balance",
    "serial number",
    "right now",
    "hours",
    "open until",
    "how much",
)

CHANNELS = ("text", "voice", "both")


class Router(nn.Module):
    """Bag-of-words embedder → reply-id logits."""

    def __init__(self, vocab: int, n_reply: int, dim: int = 32) -> None:
        super().__init__()
        self.emb = nn.Embedding(vocab, dim, padding_idx=0)
        self.head = nn.Linear(dim, n_reply)

    def forward(self, token_ids: torch.Tensor) -> torch.Tensor:
        mask = (token_ids != 0).float().unsqueeze(-1)
        e = self.emb(token_ids) * mask
        denom = mask.sum(dim=1).clamp(min=1.0)
        pooled = e.sum(dim=1) / denom
        return self.head(pooled)


def looks_inventable(text: str) -> bool:
    """True when free generate would invent without a SoT."""
    low = (text or "").lower()
    if _PRICE.search(low) or _PHONE.search(low):
        return True
    return any(m in low for m in _INVENTABLE)


def load_reply_rows(dataset_path: Path) -> list[dict[str, Any]]:
    """Load reply overlay rows; fail loud on inventable without SoT."""
    rows: list[dict[str, Any]] = []
    for line in dataset_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        raw = json.loads(line)
        msgs = raw.get("messages") or []
        user = ""
        text = ""
        for m in msgs:
            role = str(m.get("role") or "")
            content = str(m.get("content") or "").strip()
            if role == "user":
                user = content
            elif role == "assistant" and user:
                text = content
        if not user or not text:
            continue
        channel = str(raw.get("channel") or "both").strip().lower()
        if channel not in CHANNELS:
            raise ValueError(
                f"{METHOD}: bad channel {channel!r} (want text|voice|both)"
            )
        speak = str(raw.get("speak") or text).strip()
        inventable = bool(raw.get("inventable"))
        if looks_inventable(f"{user} {text}"):
            inventable = True
        sot_ref = str(raw.get("sot_ref") or "").strip() or None
        if inventable and not sot_ref:
            raise ValueError(
                f"{METHOD}: inventable row has no sot_ref "
                f"(user={user!r}) — refuse fabricate"
            )
        if sot_ref:
            sot_path = Path(sot_ref)
            if not sot_path.is_file():
                raise ValueError(
                    f"{METHOD}: sot_ref missing: {sot_ref}"
                )
            if sot_path.stat().st_size < 2:
                raise ValueError(
                    f"{METHOD}: sot_ref empty: {sot_ref}"
                )
        rows.append(
            {
                "user": user,
                "text": text,
                "speak": speak,
                "channel": channel,
                "behavior": str(raw.get("behavior") or "reply").strip(),
                "lock": bool(raw.get("lock")),
                "inventable": inventable,
                "sot_ref": sot_ref,
                "idk": str(raw.get("idk") or "I don't know.").strip(),
                "wav": str(raw.get("wav") or "").strip() or None,
            }
        )
    if not rows:
        raise ValueError(f"no reply rows in {dataset_path}")
    return rows


def train_reply_pack(
    dataset: str,
    base: str,
    out_dir: str,
    job_id: str,
    *,
    steps: int = 200,
    lr: float = 0.05,
) -> dict[str, Any]:
    """Fit reply overlay; write replies.json + gate.json + router.pt."""
    root = Path(out_dir)
    root.mkdir(parents=True, exist_ok=True)
    rows = load_reply_rows(Path(dataset))
    templates = sorted({(r["text"], r["speak"]) for r in rows})
    reply_ids = {
        t: f"r_{i:02d}" for i, t in enumerate(templates)
    }
    replies = []
    for text, speak in templates:
        sample = next(
            r for r in rows if r["text"] == text and r["speak"] == speak
        )
        replies.append(
            {
                "id": reply_ids[(text, speak)],
                "text": text,
                "speak": speak,
                "channel": sample["channel"],
                "behavior": sample["behavior"],
                "lock": sample["lock"],
                "inventable": sample["inventable"],
                "sot_ref": sample["sot_ref"],
                "idk": sample["idk"],
                "wav": sample["wav"],
            }
        )
    label = {t: i for i, t in enumerate(templates)}

    vocab: dict[str, int] = {"<pad>": 0, "<unk>": 1}
    for r in rows:
        for w in tokenize(r["user"]):
            if w not in vocab:
                vocab[w] = len(vocab)

    def encode(text: str, width: int = 32) -> torch.Tensor:
        ids = [vocab.get(w, 1) for w in tokenize(text)][:width]
        ids += [0] * (width - len(ids))
        return torch.tensor(ids, dtype=torch.long)

    xs = torch.stack([encode(r["user"]) for r in rows])
    ys = torch.tensor(
        [label[(r["text"], r["speak"])] for r in rows],
        dtype=torch.long,
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

    replies_path = root / "replies.json"
    gate_path = root / "gate.json"
    router_path = root / "router.pt"
    ckpt_path = root / "checkpoint.json"
    marker_path = root / "ARTIFACT"

    overlay_voice = any(
        r["channel"] in ("voice", "both") or r["speak"] != r["text"]
        for r in rows
    )
    gate = {
        "method": METHOD,
        "no_fabricate": True,
        "abstain_on_inventable": True,
        "require_sot_for_inventable": True,
        "overlay_voice_on_text_base": True,
        "behavior_lock": any(r["lock"] for r in rows),
        "idk": "I don't know.",
        "note": (
            "Overlay speak scripts on text-only bases. "
            "Inventable replies never open-decode — SoT or IDK."
        ),
    }
    replies_path.write_text(
        json.dumps(
            {
                "method": METHOD,
                "base": base,
                "overlay_voice_on_text_base": overlay_voice,
                "replies": replies,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    gate_path.write_text(
        json.dumps(gate, indent=2) + "\n", encoding="utf-8"
    )
    torch.save(
        {
            "method": METHOD,
            "job_id": job_id,
            "vocab": vocab,
            "reply_ids": [reply_ids[t] for t in templates],
            "state_dict": {
                k: v.cpu() for k, v in model.state_dict().items()
            },
            "dim": 32,
            "no_fabricate": True,
        },
        router_path,
    )
    meta = {
        "method": METHOD,
        "job_id": job_id,
        "base": base,
        "dataset": dataset,
        "pairs": len(rows),
        "n_replies": len(replies),
        "vocab_size": len(vocab),
        "steps": steps,
        "final_loss": round(last_loss, 6),
        "device": "cpu",
        "elapsed_s": round(time.time() - t0, 3),
        "replies": str(replies_path),
        "gate": str(gate_path),
        "router": str(router_path),
        "overlay_voice_on_text_base": overlay_voice,
        "no_fabricate": True,
        "note": (
            "Spark method: voice+text reply overlay on CPU "
            "(not LoRA, not voice-GPU, never fabricate)"
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
        replies=str(replies_path),
        gate=str(gate_path),
        no_fabricate=True,
    )
    return {
        "replies": str(replies_path),
        "gate": str(gate_path),
        "router": str(router_path),
        "weights": str(router_path),
        "checkpoint": str(ckpt_path),
        "marker": str(marker_path),
        "adapter": str(router_path),
        "meta": meta,
    }
