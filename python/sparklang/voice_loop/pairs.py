"""pairs dataset primitive — preference / reply / playbook inputs."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

SCHEMA_DEFAULT = (
    "context,target_turn,candidate_turn,"
    "score_target,score_candidate,class"
)


def _parse_schema(schema: str) -> list[str]:
    """Split comma schema into field names."""
    fields = [f.strip() for f in schema.split(",") if f.strip()]
    if not fields:
        raise ValueError("pairs schema empty")
    return fields


def load_turns(path: Path) -> list[dict[str, Any]]:
    """Load JSONL turn rows (synthetic fixtures only)."""
    rows: list[dict[str, Any]] = []
    text = path.read_text(encoding="utf-8")
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        row = json.loads(line)
        if not isinstance(row, dict):
            raise ValueError(f"pairs row not object: {path}")
        rows.append(row)
    if not rows:
        raise ValueError(f"pairs empty: {path}")
    return rows


def filter_rows(
    rows: list[dict[str, Any]],
    *,
    class_eq: str | None = None,
    min_gap: int | None = None,
) -> list[dict[str, Any]]:
    """Apply where class = … and min_gap filters."""
    out = rows
    if class_eq is not None:
        out = [r for r in out if str(r.get("class", "")) == class_eq]
    if min_gap is not None:
        kept: list[dict[str, Any]] = []
        for r in out:
            st = r.get("score_target")
            sc = r.get("score_candidate")
            if st is None or sc is None:
                continue
            try:
                gap = abs(float(st) - float(sc))
            except (TypeError, ValueError):
                continue
            if gap >= float(min_gap):
                kept.append(r)
        out = kept
    return out


def emit_pref_inputs(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Map pairs rows to pref-pack style chosen/rejected turns."""
    prefs: list[dict[str, Any]] = []
    for r in rows:
        target = str(r.get("target_turn") or "")
        cand = str(r.get("candidate_turn") or "")
        st = float(r.get("score_target") or 0)
        sc = float(r.get("score_candidate") or 0)
        chosen, rejected = (
            (target, cand) if st >= sc else (cand, target)
        )
        prefs.append(
            {
                "context": str(r.get("context") or ""),
                "chosen": chosen,
                "rejected": rejected,
                "class": str(r.get("class") or ""),
                "score_chosen": max(st, sc),
                "score_rejected": min(st, sc),
            }
        )
    return prefs


def run_pairs(
    source: str,
    schema: str = SCHEMA_DEFAULT,
    *,
    class_eq: str | None = None,
    min_gap: int | None = None,
    out_path: str | None = None,
    dry: bool = True,
) -> dict[str, Any]:
    """Load / filter pairs and write dataset artifact JSON."""
    path = Path(source)
    if not path.is_file():
        raise FileNotFoundError(f"pairs source missing: {source}")
    fields = _parse_schema(schema)
    rows = load_turns(path)
    for r in rows:
        for f in fields:
            if f not in r:
                raise ValueError(
                    f"pairs row missing field {f!r} in {source}"
                )
    filtered = filter_rows(rows, class_eq=class_eq, min_gap=min_gap)
    prefs = emit_pref_inputs(filtered)
    payload = {
        "op": "pairs",
        "mode": "dry-run" if dry else "cpu",
        "source": source,
        "schema": fields,
        "filters": {"class": class_eq, "min_gap": min_gap},
        "n_in": len(rows),
        "n_out": len(filtered),
        "pref_inputs": prefs,
        "note": "CPU pairs emit — not a trained model",
    }
    if out_path:
        dest = Path(out_path)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(
            json.dumps(payload, indent=2) + "\n",
            encoding="utf-8",
        )
        payload["artifact"] = str(dest)
    return payload


_CLASS_RE = re.compile(
    r'where\s+class\s*=\s*"([^"]*)"',
    re.I,
)
_GAP_RE = re.compile(r"min_gap\s+(\d+)", re.I)
_FROM_RE = re.compile(r'from\s+"([^"]+)"', re.I)
_SCHEMA_RE = re.compile(r'schema\s+"([^"]+)"', re.I)
_ARROW_RE = re.compile(r"->\s*([A-Za-z_][A-Za-z0-9_]*)\s*$")


def parse_pairs_stmt(stmt: str) -> dict[str, Any]:
    """Parse ``model pairs from … schema … [where…] [min_gap N] -> id``."""
    s = stmt.strip()
    if not re.match(r"^(model\s+)?pairs\b", s, re.I):
        raise ValueError("not a pairs statement")
    m_from = _FROM_RE.search(s)
    if not m_from:
        raise ValueError('pairs needs from "path"')
    m_schema = _SCHEMA_RE.search(s)
    schema = m_schema.group(1) if m_schema else SCHEMA_DEFAULT
    m_cls = _CLASS_RE.search(s)
    m_gap = _GAP_RE.search(s)
    m_bind = _ARROW_RE.search(s)
    return {
        "source": m_from.group(1),
        "schema": schema,
        "class_eq": m_cls.group(1) if m_cls else None,
        "min_gap": int(m_gap.group(1)) if m_gap else None,
        "bind": m_bind.group(1) if m_bind else None,
    }
