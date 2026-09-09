"""Grounded ask — refuse unless dump / fixture / expect match.

Mode that makes guessing fail CI: wrong expect → abstain.
Optional JSON-schema verify (stdlib subset; no xgrammar dep).
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any, Optional

from sparklang.abstain.inventable import (
    looks_inventable,
    outer_verify_or_refuse,
)
from sparklang.ground.cite import cite_sources
from sparklang.ground.schema import validate_json_schema

_IDK = "I don't know."


def _read_text(path: str | Path) -> str:
    """Read UTF-8 text from a fixture or dump path."""
    return Path(path).read_text(encoding="utf-8").strip()


def _normalize(s: str) -> str:
    """Collapse whitespace for contain / equal checks."""
    return re.sub(r"\s+", " ", (s or "").strip())


def _expect_ok(
    candidate: str,
    *,
    expect: Optional[str],
    expect_mode: str,
) -> tuple[bool, str]:
    """Match candidate against an expect string."""
    if expect is None:
        return True, "no_expect"
    got = _normalize(candidate)
    want = _normalize(expect)
    mode = (expect_mode or "equal").lower()
    if mode == "equal":
        if got == want:
            return True, "expect_equal"
        return False, "expect_equal_miss"
    if mode == "contains":
        if want in got:
            return True, "expect_contains"
        return False, "expect_contains_miss"
    return False, f"bad_expect_mode:{mode}"


def _dump_grounded(candidate: str, dump: Path) -> tuple[bool, str]:
    """True when candidate text appears in dump facts."""
    raw = _read_text(dump)
    if not raw:
        return False, "dump_empty"
    if _normalize(candidate) in _normalize(raw):
        return True, "dump_contains"
    # Allow opcode / sha tokens as dump-grounded answers
    tokens = re.findall(r"[A-Za-z0-9_.-]{3,}", candidate)
    if tokens and all(t in raw for t in tokens):
        return True, "dump_tokens"
    return False, "dump_miss"


def verify_before_speak(
    candidate: Optional[str],
    *,
    expect: Optional[str] = None,
    expect_mode: str = "equal",
    fixture: Optional[str | Path] = None,
    dump: Optional[str | Path] = None,
    retrieve_hits: Optional[list[str]] = None,
    schema: Optional[dict[str, Any]] = None,
    require_ground: bool = True,
) -> dict[str, Any]:
    """Verify a proposed answer before it is spoken.

    Wrong expect / fixture / dump / schema → abstain + halt.
    """
    cites = cite_sources(
        expect=expect,
        fixture=str(fixture) if fixture else None,
        dump=str(dump) if dump else None,
        retrieve_hits=retrieve_hits,
    )
    if candidate is None or not str(candidate).strip():
        return {
            "op": "verify",
            "abstain": True,
            "halted": True,
            "reason": "empty_candidate",
            "text": _IDK,
            "cites": cites,
        }
    text = str(candidate).strip()

    if fixture is not None:
        want = _read_text(fixture)
        ok, reason = _expect_ok(
            text, expect=want, expect_mode=expect_mode
        )
        if not ok:
            return {
                "op": "verify",
                "abstain": True,
                "halted": True,
                "reason": reason,
                "text": _IDK,
                "cites": cites,
                "want": want,
                "got": text,
            }

    if expect is not None:
        ok, reason = _expect_ok(
            text, expect=expect, expect_mode=expect_mode
        )
        if not ok:
            return {
                "op": "verify",
                "abstain": True,
                "halted": True,
                "reason": reason,
                "text": _IDK,
                "cites": cites,
                "want": expect,
                "got": text,
            }

    if dump is not None:
        ok, reason = _dump_grounded(text, Path(dump))
        if not ok:
            return {
                "op": "verify",
                "abstain": True,
                "halted": True,
                "reason": reason,
                "text": _IDK,
                "cites": cites,
            }

    if retrieve_hits:
        joined = "\n".join(retrieve_hits)
        if _normalize(text) not in _normalize(joined) and not any(
            _normalize(h) in _normalize(text) for h in retrieve_hits
        ):
            return {
                "op": "verify",
                "abstain": True,
                "halted": True,
                "reason": "retrieve_miss",
                "text": _IDK,
                "cites": cites,
            }

    if schema is not None:
        try:
            parsed: Any = json.loads(text)
        except json.JSONDecodeError:
            return {
                "op": "verify",
                "abstain": True,
                "halted": True,
                "reason": "schema_json_parse",
                "text": _IDK,
                "cites": cites,
            }
        ok, err = validate_json_schema(parsed, schema)
        if not ok:
            return {
                "op": "verify",
                "abstain": True,
                "halted": True,
                "reason": f"schema:{err}",
                "text": _IDK,
                "cites": cites,
            }

    grounded = bool(
        expect is not None
        or fixture is not None
        or dump is not None
        or retrieve_hits
        or schema is not None
    )
    if require_ground and not grounded:
        return {
            "op": "verify",
            "abstain": True,
            "halted": True,
            "reason": "ungrounded",
            "text": _IDK,
            "cites": cites,
            "note": (
                "grounded mode refuses free generate without "
                "expect / fixture / dump / retrieve / schema"
            ),
        }

    return {
        "op": "verify",
        "abstain": False,
        "halted": False,
        "reason": "verified",
        "text": text,
        "cites": cites,
    }


def grounded_ask(
    prompt: str,
    *,
    candidate: Optional[str] = None,
    expect: Optional[str] = None,
    expect_mode: str = "equal",
    fixture: Optional[str | Path] = None,
    dump: Optional[str | Path] = None,
    retrieve_hits: Optional[list[str]] = None,
    schema: Optional[dict[str, Any]] = None,
    sot_ok: bool = False,
    tool_allowlist: Optional[list[str]] = None,
    tool_requested: Optional[str] = None,
    require_ground: bool = True,
    idk: str = _IDK,
) -> dict[str, Any]:
    """Refuse to answer unless grounding evidence matches.

    Order: tool allowlist → inventable outer gate → verify.
    """
    if tool_requested:
        allow = set(tool_allowlist or [])
        if tool_requested not in allow:
            return {
                "op": "grounded_ask",
                "abstain": True,
                "halted": True,
                "reason": "tool_denied",
                "text": idk,
                "prompt": prompt,
                "tool_requested": tool_requested,
                "tool_allowlist": sorted(allow),
            }

    outer = outer_verify_or_refuse(
        prompt, sot_ok=sot_ok, idk=idk
    )
    if outer.get("abstain"):
        outer = dict(outer)
        outer["op"] = "grounded_ask"
        return outer

    # Inventable with SoT still needs verify when candidate given
    if looks_inventable(prompt) and candidate is None and (
        require_ground
        and not (
            expect
            or fixture
            or dump
            or retrieve_hits
            or schema
        )
    ):
        return {
            "op": "grounded_ask",
            "abstain": True,
            "halted": True,
            "reason": "inventable_no_candidate",
            "text": idk,
            "prompt": prompt,
            "note": (
                "inventable prompts need SoT quote + verify; "
                "do not open-decode"
            ),
        }

    verified = verify_before_speak(
        candidate,
        expect=expect,
        expect_mode=expect_mode,
        fixture=fixture,
        dump=dump,
        retrieve_hits=retrieve_hits,
        schema=schema,
        require_ground=require_ground,
    )
    out = dict(verified)
    out["op"] = "grounded_ask"
    out["prompt"] = prompt
    out["sot_ok"] = sot_ok
    if out.get("abstain") and idk != _IDK:
        out["text"] = idk
    return out
