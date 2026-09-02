"""Labeled abstain corpus — schema, validate, load.

Honest seed format for ``head train`` / ``export``. This is **not** a
production accuracy corpus. Grow it by appending curated JSONL rows;
never invent a fake large dataset or claim LM gate quality from fixtures.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Optional, Union

PathLike = Union[str, Path]

# 0 = answer (SAMPLE OK); 1 = abstain (prefer IDK / halt)
LABEL_ANSWER = 0
LABEL_ABSTAIN = 1

# Row sources — keep honest about feature origin.
SOURCE_TEXT = "text"
SOURCE_TOY = "toy"
SOURCE_SYNTHETIC = "synthetic_backbone"
SOURCE_HF = "hf"
SOURCE_BAG_HASH = "bag_hash"

_VALID_SOURCES = frozenset(
    {
        SOURCE_TEXT,
        SOURCE_TOY,
        SOURCE_SYNTHETIC,
        SOURCE_HF,
        SOURCE_BAG_HASH,
        "toy_stub",
        "hf_prefill",
        "file",
    }
)


def label_name(label: int) -> str:
    """Human name for a 0/1 abstain label."""
    if int(label) == LABEL_ABSTAIN:
        return "abstain"
    if int(label) == LABEL_ANSWER:
        return "answer"
    raise ValueError(f"label must be 0 or 1, got {label!r}")


def normalize_row(row: dict[str, Any]) -> dict[str, Any]:
    """Normalize one JSONL object into the corpus schema.

    Required: ``text`` (or ``prompt``) + ``label`` (or ``abstain``) as
    0/1. Optional: ``reason``, ``id``, ``tags``, ``hidden``, ``dim``,
    ``source``, ``kind``, ``label_name``.
    """
    if not isinstance(row, dict):
        raise ValueError(f"row must be object, got {type(row)}")
    text = row.get("text")
    if text is None:
        text = row.get("prompt")
    if text is None or not str(text).strip():
        raise ValueError(f"row needs non-empty text/prompt: {row!r}")
    label = row.get("label")
    if label is None:
        label = row.get("abstain")
    if label is None:
        # Accept string label_name only when label int missing.
        name = row.get("label_name")
        if isinstance(name, str):
            low = name.strip().lower()
            if low in ("abstain", "idk", "refuse", "1"):
                label = LABEL_ABSTAIN
            elif low in ("answer", "respond", "0"):
                label = LABEL_ANSWER
        if label is None:
            raise ValueError(f"row needs label/abstain: {row!r}")
    label_i = int(label)
    if label_i not in (LABEL_ANSWER, LABEL_ABSTAIN):
        raise ValueError(
            f"label must be 0 (answer) or 1 (abstain), got {label_i}"
        )
    out: dict[str, Any] = {
        "text": str(text).strip(),
        "label": label_i,
        "label_name": label_name(label_i),
    }
    reason = row.get("reason")
    if reason is not None and str(reason).strip():
        out["reason"] = str(reason).strip()
    rid = row.get("id")
    if rid is not None and str(rid).strip():
        out["id"] = str(rid).strip()
    tags = row.get("tags")
    if isinstance(tags, list):
        out["tags"] = [str(t) for t in tags]
    elif tags is not None and str(tags).strip():
        out["tags"] = [str(tags).strip()]
    hidden = row.get("hidden") or row.get("features")
    if hidden is not None:
        if not isinstance(hidden, list) or not hidden:
            raise ValueError("hidden must be non-empty float list")
        feats = [float(x) for x in hidden]
        out["hidden"] = feats
        dim = int(row.get("dim") or len(feats))
        if dim != len(feats):
            raise ValueError(
                f"dim {dim} != len(hidden) {len(feats)}"
            )
        out["dim"] = dim
    elif row.get("dim") is not None:
        out["dim"] = int(row["dim"])
    source = row.get("source")
    if source is not None:
        src = str(source).strip()
        if src and src not in _VALID_SOURCES:
            # Allow unknown with prefix for forward-compat; still stamp.
            if not src.replace("_", "").isalnum():
                raise ValueError(f"bad source {src!r}")
        out["source"] = src or SOURCE_TEXT
    kind = row.get("kind")
    if kind is not None and str(kind).strip():
        out["kind"] = str(kind).strip()
    return out


def load_corpus(
    path: PathLike,
    *,
    require_hidden: bool = False,
) -> list[dict[str, Any]]:
    """Load and normalize JSONL corpus rows."""
    p = Path(path)
    if not p.is_file():
        raise FileNotFoundError(f"corpus missing: {p}")
    rows: list[dict[str, Any]] = []
    for i, line in enumerate(
        p.read_text(encoding="utf-8").splitlines(), start=1
    ):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            raw = json.loads(line)
            row = normalize_row(raw)
        except (json.JSONDecodeError, ValueError) as exc:
            raise ValueError(f"{p}:{i}: {exc}") from exc
        if require_hidden and "hidden" not in row:
            raise ValueError(f"{p}:{i}: hidden required")
        rows.append(row)
    if not rows:
        raise ValueError(f"empty corpus: {p}")
    return rows


def validate_corpus(
    path: PathLike,
    *,
    require_hidden: bool = False,
    min_answer: int = 1,
    min_abstain: int = 1,
) -> dict[str, Any]:
    """Validate corpus file; return summary (raises on hard errors)."""
    rows = load_corpus(path, require_hidden=require_hidden)
    n_answer = sum(1 for r in rows if r["label"] == LABEL_ANSWER)
    n_abstain = sum(1 for r in rows if r["label"] == LABEL_ABSTAIN)
    dims = {r.get("dim") for r in rows if "dim" in r}
    sources = sorted(
        {str(r.get("source") or SOURCE_TEXT) for r in rows}
    )
    warnings: list[str] = []
    if n_answer < min_answer:
        warnings.append(
            f"few answer rows ({n_answer} < {min_answer})"
        )
    if n_abstain < min_abstain:
        warnings.append(
            f"few abstain rows ({n_abstain} < {min_abstain})"
        )
    if len(dims) > 1:
        raise ValueError(f"mixed hidden dims in corpus: {dims}")
    # Honest quality stamp — never claim production accuracy.
    quality = "fixture_seed"
    if any(
        str(r.get("source") or "") in (SOURCE_HF, "hf_prefill")
        for r in rows
    ):
        quality = "hf_exported_unverified"
    elif any(
        str(r.get("source") or "") == SOURCE_SYNTHETIC
        for r in rows
    ):
        quality = "synthetic_backbone_dim_match"
    elif any(
        str(r.get("source") or "") in (SOURCE_TOY, "toy_stub")
        for r in rows
    ):
        quality = "toy_backbone"
    return {
        "op": "corpus_validate",
        "path": str(path),
        "n": len(rows),
        "n_answer": n_answer,
        "n_abstain": n_abstain,
        "dims": sorted(d for d in dims if d is not None),
        "sources": sources,
        "quality": quality,
        "warnings": warnings,
        "note": (
            "seed/fixture only — not production accuracy; "
            "retrain on target-backbone hiddens before claims"
        ),
        "state": "ok",
    }


def write_corpus(
    rows: list[dict[str, Any]],
    path: PathLike,
    *,
    compact: bool = True,
) -> Path:
    """Write normalized rows as JSONL."""
    out = Path(path)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", encoding="utf-8") as fh:
        for raw in rows:
            row = normalize_row(raw)
            if compact:
                fh.write(
                    json.dumps(row, separators=(",", ":")) + "\n"
                )
            else:
                fh.write(json.dumps(row) + "\n")
    return out
