"""Inventable-fact helpers — outer verify-or-refuse compose.

The abstain head alone is not enough for prices / IDs / live
ledger facts. Prefer SoT / HTTP / ``expect`` **before** free
generate. This module is the dry / CLI helper for that layer.

Default: inventable + no SoT → ``I don't know.`` (no sample).
"""

from __future__ import annotations

import re
from typing import Any, Optional


# Prompts that look inventable without an external SoT.
_INVENTABLE_MARKERS = (
    "mayor of",
    "mayor",
    "who is the current",
    "who is the",
    "who was the",
    "who called",
    "who worked",
    "who won",
    "who is president",
    "price at",
    "how much",
    "how many dollars",
    "dryer start",
    "card balance",
    "right now",
    "this minute",
    "this hour",
    "serial number",
    "revenue for",
    "exact unpaid",
    "live gps",
    "badge id",
    "cash in drawer",
    "winning lottery",
    "will aapl",
    "stock price",
    "close at friday",
    "weather",
    "forecast",
    "temperature in",
    "your hours",
    "open until",
    "open at",
    "are you open",
    "phone number",
    "phone #",
    "capital of",
    "population of",
    "born in",
    "when was",
    "when did",
    "how old is",
    "latest score",
    "election result",
)

_REFUSE_MARKERS = (
    "ssn",
    "password",
    "api key",
    "jwt",
    "private key",
    "routing number",
    "ein",
    "cvv",
    "2fa",
    "otp",
    "wifi password",
    "door code",
    "alarm",
    "fingerprint",
    "home street",
    "cell number",
    "prescription",
)

_SAFE_CODE = (
    "explain",
    "rename",
    "refactor",
    "unit test",
    "endpoint",
    "debug",
    "translate",
    "summar",
    "reply with",
)

_PRICE = re.compile(r"\$\s*\d|\d+\.\d{2}")
_PHONE = re.compile(r"\b\d{3}[-.\s]?\d{3}[-.\s]?\d{4}\b")
_MATH = re.compile(
    r"\bwhat(?:'s| is)\s+\d+\s*[+\-*/x×]\s*\d+",
    re.I,
)


def _is_safe_code(low: str) -> bool:
    """Coding / playbook verbs that may continue without SoT."""
    stripped = (low or "").strip()
    if stripped in ("ping", "pong"):
        return True
    return any(s in low for s in _SAFE_CODE)


def is_closed_math(prompt: str) -> bool:
    """True for closed arithmetic like ``what is 2+2``."""
    return bool(_MATH.search(prompt or ""))


def looks_inventable(prompt: str) -> bool:
    """True when free generate would invent without SoT.

    Coding playbook verbs continue **unless** a live-fact marker
    is also present. Closed arithmetic is never inventable.
    """
    low = (prompt or "").lower()
    if any(m in low for m in _REFUSE_MARKERS):
        return True
    if _PRICE.search(low) or _PHONE.search(low):
        return True
    if is_closed_math(prompt):
        return False
    if any(m in low for m in _INVENTABLE_MARKERS):
        return True
    if _is_safe_code(low):
        return False
    return False


def outer_verify_or_refuse(
    prompt: str,
    *,
    sot_ok: bool,
    idk: str = "I don't know.",
    sot_note: Optional[str] = None,
) -> dict[str, Any]:
    """Outer gate: inventable + missing SoT → refuse + halt.

    When ``sot_ok`` is True, caller may continue to SAMPLE / head
    ask. When False and the prompt looks inventable, return IDK
    with ``reason=outer_verify``.
    """
    inventable = looks_inventable(prompt)
    if inventable and not sot_ok:
        return {
            "op": "outer_verify",
            "abstain": True,
            "halted": True,
            "reason": "outer_verify",
            "inventable": True,
            "sot_ok": False,
            "text": idk,
            "prompt": prompt,
            "note": sot_note
            or (
                "refuse inventable fact without SoT / "
                "HTTP expect — compose before free generate"
            ),
        }
    return {
        "op": "outer_verify",
        "abstain": False,
        "halted": False,
        "reason": "continue",
        "inventable": inventable,
        "sot_ok": sot_ok,
        "text": None,
        "prompt": prompt,
    }
