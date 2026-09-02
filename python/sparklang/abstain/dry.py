"""Dry-run fixtures for head ops (no GPU / no network)."""

from __future__ import annotations

import json
from typing import Any


def dry_result(fields: dict[str, Any]) -> dict[str, Any]:
    """Compact JSON suitable for set_last (≤1023 chars)."""
    op = fields.get("op")
    kind = fields.get("kind") or "internal"
    if op == "abstain":
        return {
            "op": "head_abstain",
            "mode": "dry-run",
            "kind": kind,
            "threshold": float(fields.get("threshold") or 0.7),
            "idk": fields.get("idk") or "I don't know.",
            "model": fields.get("model") or "fixture-model",
            "weights": fields.get("weights")
            or "out/heads/abstain.pt",
            "state": "ready",
            "note": "dry-run - head not loaded",
        }
    if op == "train":
        out = fields.get("out") or "out/heads/abstain.pt"
        return {
            "op": "head_train",
            "mode": "dry-run",
            "kind": kind,
            "dataset": fields.get("dataset")
            or "examples/fixtures/abstain/labels.jsonl",
            "out": out,
            "hidden_dim": int(fields.get("hidden_dim") or 64),
            "state": "accepted",
            "job_id": "head-dry-001",
            "note": "dry-run - weights not trained on this host",
        }
    if op == "attach":
        return {
            "op": "head_attach",
            "mode": "dry-run",
            "kind": kind,
            "model": fields.get("model") or "fixture-model",
            "weights": fields.get("weights")
            or "out/heads/abstain.pt",
            "manifest": fields.get("out")
            or "out/heads/manifest.json",
            "state": "succeeded",
            "note": "dry-run - manifest not written",
        }
    if op == "ask":
        prompt = fields.get("prompt") or ""
        # Deterministic dry gate: unknown-ish prompts abstain.
        low = prompt.lower()
        inventable = any(
            k in low
            for k in (
                "mayor",
                "who is",
                "ssn",
                "password",
                "invent",
                "api key",
                "dryer start",
                "price at",
                "right now",
                "card balance",
                "serial number",
            )
        )
        if inventable:
            idk = fields.get("idk") or "I don't know."
            return {
                "op": "head_ask",
                "mode": "dry-run",
                "abstain": True,
                "halted": True,
                "p_abstain": 0.91,
                "reason": "threshold",
                "text": idk,
                "prompt": prompt,
            }
        return {
            "op": "head_ask",
            "mode": "dry-run",
            "abstain": False,
            "halted": False,
            "p_abstain": 0.12,
            "reason": "continue",
            "text": "Gravity pulls masses together.",
            "prompt": prompt,
        }
    raise ValueError(f"unknown head op: {op}")


def dumps_compact(obj: dict[str, Any]) -> str:
    """Single-line JSON for GAS bind buffer."""
    return json.dumps(obj, separators=(",", ":"))
