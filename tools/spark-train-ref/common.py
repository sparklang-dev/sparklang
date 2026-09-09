#!/usr/bin/env python3
"""Shared helpers for SparkLang CPU train methods."""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")

_PY = Path(__file__).resolve().parents[2] / "python"
if str(_PY) not in sys.path:
    sys.path.insert(0, str(_PY))
from sparklang.abstain.inventable import looks_inventable

_WORD = re.compile(r"[a-z0-9']+", re.I)

METHODS = (
    "spark_distill_cpu",
    "spark_pref_pack",
    "spark_playbook_fit",
    "spark_faq_index",
    "spark_reply_pack",
)


def load_pairs(dataset_path: Path) -> list[tuple[str, str]]:
    """Load (user, assistant) pairs from chat-style JSONL."""
    out: list[tuple[str, str]] = []
    for line in dataset_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        row = json.loads(line)
        msgs = row.get("messages") or []
        user = ""
        for m in msgs:
            role = str(m.get("role") or "")
            content = str(m.get("content") or "").strip()
            if role == "user":
                user = content
            elif role == "assistant" and user:
                sot = str(row.get("sot_ref") or "").strip()
                blob = f"{user}\n{content}"
                if looks_inventable(blob):
                    sot_path = Path(sot) if sot else None
                    if not sot_path or not sot_path.is_file():
                        raise ValueError(
                            "refuse fabricate: inventable row "
                            f"needs sot_ref file (user={user!r})"
                        )
                    if sot_path.stat().st_size < 2:
                        raise ValueError(
                            "refuse fabricate: sot_ref empty: "
                            f"{sot}"
                        )
                out.append((user, content))
                user = ""
    if not out:
        raise ValueError(f"no user/assistant pairs in {dataset_path}")
    return out


def tokenize(text: str) -> list[str]:
    """Lowercase word tokens (fallback <empty>)."""
    return _WORD.findall(text.lower()) or ["<empty>"]


def write_marker(
    path: Path, method: str, job_id: str, primary: str, **extra: object
) -> None:
    """Write ARTIFACT stamp for a finished job."""
    lines = [f"{method} {job_id}", f"primary={primary}"]
    for k, v in extra.items():
        lines.append(f"{k}={v}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
