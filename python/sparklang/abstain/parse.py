"""Parse ``head …`` SparkLang statements into structured dicts."""

from __future__ import annotations

import re
from typing import Any, Optional

_Q = re.compile(r'"([^"\\]|\\.)*"')
_KV = re.compile(
    r"(dataset|model|weights|out|kind|idk|threshold|"
    r"hidden_dim|entropy|margin)\s+"
    r'(?:"((?:[^"\\]|\\.)*)"|([0-9.]+)|'
    r"(internal|external)\b)"
)


def _unquote(s: str) -> str:
    if len(s) >= 2 and s[0] == '"' and s[-1] == '"':
        return bytes(s[1:-1], "utf-8").decode("unicode_escape")
    return s


def parse_head_stmt(stmt: str) -> dict[str, Any]:
    """Parse one head line into op + fields.

    Forms::

      head abstain internal|external …
      head train …
      head attach …
      head ask "…"
    """
    line = stmt.strip()
    if line.startswith("#"):
        raise ValueError("comment line")
    if not line.startswith("head"):
        raise ValueError("not a head statement")
    rest = line[4:].lstrip()
    bind: Optional[str] = None
    if "->" in rest:
        rest, arrow = rest.rsplit("->", 1)
        bind = arrow.strip().split()[0] if arrow.strip() else None
        rest = rest.rstrip()
    fields: dict[str, Any] = {"bind": bind, "raw": stmt.strip()}
    if rest.startswith("ask"):
        fields["op"] = "ask"
        m = _Q.search(rest)
        if not m:
            raise ValueError('head ask needs a quoted prompt')
        fields["prompt"] = _unquote(m.group(0))
        return fields
    if rest.startswith("train"):
        fields["op"] = "train"
        fields["kind"] = "internal"
    elif rest.startswith("attach"):
        fields["op"] = "attach"
        fields["kind"] = "internal"
    elif rest.startswith("abstain"):
        fields["op"] = "abstain"
        after = rest[len("abstain") :].lstrip()
        if after.startswith("internal"):
            fields["kind"] = "internal"
        elif after.startswith("external"):
            fields["kind"] = "external"
        else:
            raise ValueError(
                "head abstain needs internal|external"
            )
    else:
        raise ValueError(
            "head needs abstain|train|attach|ask"
        )
    for m in _KV.finditer(rest):
        key = m.group(1)
        if m.group(2) is not None:
            fields[key] = m.group(2).replace('\\"', '"')
        elif m.group(3) is not None:
            val = m.group(3)
            fields[key] = float(val) if "." in val else int(val)
        elif m.group(4) is not None:
            fields[key] = m.group(4)
    if fields["op"] == "train" and "kind" not in fields:
        fields["kind"] = "internal"
    return fields
