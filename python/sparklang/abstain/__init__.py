"""Abstain / IDK heads for SparkLang local generate.

SELECT before SAMPLE: if p(abstain|h) ≥ τ → emit IDK + halt.
Internal = probe on frozen backbone; external = sidecar scorer.
"""

from __future__ import annotations

from sparklang.abstain.attach import attach_head, load_manifest
from sparklang.abstain.gate import GateConfig, GateDecision, select_before_sample
from sparklang.abstain.head import AbstainHead, head_from_state
from sparklang.abstain.parse import parse_head_stmt
from sparklang.abstain.train import train_abstain_head

__all__ = [
    "AbstainHead",
    "GateConfig",
    "GateDecision",
    "attach_head",
    "head_from_state",
    "load_manifest",
    "parse_head_stmt",
    "select_before_sample",
    "train_abstain_head",
]
