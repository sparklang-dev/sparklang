"""Inventable-fact helpers — outer verify-or-refuse compose.

The abstain head alone is not enough for prices / IDs / live
ledger facts. Prefer SoT / HTTP / ``expect`` **before** free
generate. This module is the dry / CLI helper for that layer.
"""

from __future__ import annotations

from typing import Any, Optional


# Prompts that look inventable without an external SoT.
_INVENTABLE_MARKERS = (
    "mayor of",
    "who is the current",
    "price at",
    "dryer start",
    "card balance",
    "right now",
    "this minute",
    "serial number",
    "who called",
    "who worked",
    "revenue for tomorrow",
    "exact unpaid",
    "live gps",
    "badge id",
    "cash in drawer",
    "winning lottery",
    "will aapl",
    "close at friday",
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


def looks_inventable(prompt: str) -> bool:
    """True when free generate would invent without SoT."""
    low = (prompt or "").lower()
    if any(m in low for m in _REFUSE_MARKERS):
        return True
    if any(m in low for m in _INVENTABLE_MARKERS):
        return True
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
