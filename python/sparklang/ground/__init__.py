"""Spark grounded generation — anti-guess / verify-before-speak.

Forced grounding for Qwen-class and Spark-owned models. Does **not**
claim literal impossibility of all lies. Makes guessing fail CI via
expect / fixture / dump / schema gates and abstain.

Prefer RTX **5090** for opt-in external SFT; **never** RTX PRO **6000**.
Does **not** beat Claude.
"""

from __future__ import annotations

from sparklang.ground.adapter import (
    AdapterSpec,
    attach_adapter_manifest,
    device_policy,
)
from sparklang.ground.cite import cite_sources
from sparklang.ground.gate import grounded_ask, verify_before_speak
from sparklang.ground.schema import validate_json_schema

__all__ = [
    "AdapterSpec",
    "attach_adapter_manifest",
    "cite_sources",
    "device_policy",
    "grounded_ask",
    "validate_json_schema",
    "verify_before_speak",
]
