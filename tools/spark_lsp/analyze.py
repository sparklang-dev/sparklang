#!/usr/bin/env python3
"""Static checks for .spark buffers (LSP diagnostics)."""

from __future__ import annotations

import json
import re
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_KW_PATH = _HERE / "keywords.json"

_EXPECT = re.compile(
    r"^\s*expect\s+(equal|contains)\s+(\w+)\b",
    re.MULTILINE,
)
_LET_BIND = re.compile(
    r"^\s*(?:let|classify|ask|retrieve|embed|extract|shell|run|"
    r"train|status|http|ide|head)\b.*?->\s*(\w+)\s*$",
    re.MULTILINE,
)
_LET = re.compile(r"^\s*let\s+(\w+)\b", re.MULTILINE)


def load_catalog() -> dict:
    """Load keyword / alias / hover catalog from keywords.json."""
    return json.loads(_KW_PATH.read_text(encoding="utf-8"))


def _bound_names(text: str) -> set[str]:
    names = set(_LET.findall(text))
    names.update(_LET_BIND.findall(text))
    return names


def diagnose(text: str) -> list[dict]:
    """Return LSP-shaped diagnostics for a .spark buffer."""
    diags: list[dict] = []
    lines = text.splitlines()
    bound = _bound_names(text)

    # Unclosed double-quote (simple line scan; ignore # comments).
    for i, line in enumerate(lines):
        code = line.split("#", 1)[0]
        n_q = 0
        esc = False
        for ch in code:
            if esc:
                esc = False
                continue
            if ch == "\\":
                esc = True
                continue
            if ch == '"':
                n_q += 1
        if n_q % 2 == 1:
            diags.append(
                {
                    "severity": "Warning",
                    "message": "Unclosed string on this line",
                    "line": i,
                    "character": 0,
                    "endCharacter": max(len(line), 1),
                    "source": "spark-lsp",
                    "code": "unclosed-string",
                }
            )

    for m in _EXPECT.finditer(text):
        name = m.group(2)
        if name not in bound:
            line = text.count("\n", 0, m.start())
            col = m.start() - (text.rfind("\n", 0, m.start()) + 1)
            diags.append(
                {
                    "severity": "Error",
                    "message": (
                        f"expect target '{name}' is not bound "
                        f"(let / -> name) in this file"
                    ),
                    "line": line,
                    "character": col,
                    "endCharacter": col + len(m.group(0).strip()),
                    "source": "spark-lsp",
                    "code": "expect-unbound",
                }
            )

    return diags


def hover_for(word: str) -> str | None:
    """Return hover markdown for a keyword, or None."""
    catalog = load_catalog()
    hover = catalog.get("hover") or {}
    if word in hover:
        return f"**{word}** — {hover[word]}"
    if word in catalog.get("aliases", []):
        return f"**{word}** — model alias (gateway / dry)"
    if word in catalog.get("keywords", []):
        return f"**{word}** — SparkLang keyword"
    return None


def completions(prefix: str = "") -> list[dict]:
    """Completion items filtered by prefix."""
    catalog = load_catalog()
    items: list[dict] = []
    for kw in catalog["keywords"]:
        if prefix and not kw.startswith(prefix):
            continue
        items.append(
            {
                "label": kw,
                "kind": 14,  # Keyword
                "detail": "SparkLang",
                "documentation": (catalog.get("hover") or {}).get(kw, ""),
            }
        )
    for al in catalog["aliases"]:
        if prefix and not al.startswith(prefix):
            continue
        items.append(
            {
                "label": al,
                "kind": 12,  # Value
                "detail": "model alias",
                "documentation": "Spark model alias",
            }
        )
    return items
