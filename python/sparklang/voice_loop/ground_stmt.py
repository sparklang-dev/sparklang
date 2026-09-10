"""ground fact — verify-before-speak for numbers / hours / names."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any


def _load_facts(path: Path) -> dict[str, Any]:
    """Load a JSON object of fact_key → value."""
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError(f"facts must be a JSON object: {path}")
    return raw


def run_ground_fact(
    key: str,
    facts_path: str,
    *,
    else_mode: str = "abstain",
    dry: bool = True,
) -> dict[str, Any]:
    """Lookup key in facts; abstain or fail when missing."""
    path = Path(facts_path)
    if not path.is_file():
        raise FileNotFoundError(f"ground facts missing: {facts_path}")
    facts = _load_facts(path)
    if key in facts and facts[key] is not None and str(facts[key]) != "":
        val = facts[key]
        return {
            "op": "ground",
            "mode": "dry-run" if dry else "cpu",
            "key": key,
            "value": val,
            "abstain": False,
            "source": facts_path,
            "note": "grounded from facts file",
        }
    if else_mode == "abstain":
        return {
            "op": "ground",
            "mode": "dry-run" if dry else "cpu",
            "key": key,
            "value": None,
            "abstain": True,
            "text": "I don't know.",
            "source": facts_path,
            "note": "missing fact — abstain",
        }
    raise KeyError(f"ground fact missing key {key!r}")


_GROUND_RE = re.compile(
    r'ground\s+fact\s+"([^"]+)"\s+from\s+"([^"]+)"'
    r'(?:\s+else\s+(abstain|fail))?',
    re.I,
)


def parse_ground_stmt(stmt: str) -> dict[str, str]:
    """Parse ``ground fact "k" from "facts.json" else abstain``."""
    m = _GROUND_RE.search(stmt.strip())
    if not m:
        raise ValueError(
            'ground needs: fact "key" from "path" [else abstain|fail]'
        )
    return {
        "key": m.group(1),
        "facts_path": m.group(2),
        "else_mode": (m.group(3) or "abstain").lower(),
    }
