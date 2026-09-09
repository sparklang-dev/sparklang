"""Citation helpers for grounded answers."""

from __future__ import annotations

from typing import Any, Optional


def cite_sources(
    *,
    expect: Optional[str] = None,
    fixture: Optional[str] = None,
    dump: Optional[str] = None,
    retrieve_hits: Optional[list[str]] = None,
    manifest: Optional[str] = None,
) -> list[dict[str, Any]]:
    """Build a cite list for verify-before-speak payloads."""
    cites: list[dict[str, Any]] = []
    if expect is not None:
        cites.append({"kind": "expect", "value": expect})
    if fixture:
        cites.append({"kind": "fixture", "path": fixture})
    if dump:
        cites.append({"kind": "dump", "path": dump})
    if retrieve_hits:
        for i, hit in enumerate(retrieve_hits):
            cites.append(
                {"kind": "retrieve", "rank": i, "text": hit}
            )
    if manifest:
        cites.append({"kind": "adapter_manifest", "path": manifest})
    return cites
