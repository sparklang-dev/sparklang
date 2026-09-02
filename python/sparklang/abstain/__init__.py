"""Abstain / IDK heads for SparkLang local generate.

SELECT before SAMPLE: if p(abstain|h) ≥ τ → emit IDK + halt.
Internal = probe on frozen backbone; external = sidecar scorer.
"""

from __future__ import annotations

from sparklang.abstain.attach import attach_head, load_manifest
from sparklang.abstain.export import export_hiddens, toy_backbone_hidden
from sparklang.abstain.gate import GateConfig, GateDecision, select_before_sample
from sparklang.abstain.generate import live_ask, score_hidden
from sparklang.abstain.head import AbstainHead, head_from_state
from sparklang.abstain.parse import parse_head_stmt
from sparklang.abstain.spark_hidden import (
    SparkHiddenRequest,
    SparkHiddenResponse,
    parse_request,
    parse_response,
    post_spark_hidden,
)
from sparklang.abstain.train import train_abstain_head

__all__ = [
    "AbstainHead",
    "GateConfig",
    "GateDecision",
    "SparkHiddenRequest",
    "SparkHiddenResponse",
    "attach_head",
    "export_hiddens",
    "head_from_state",
    "live_ask",
    "load_manifest",
    "parse_head_stmt",
    "parse_request",
    "parse_response",
    "post_spark_hidden",
    "score_hidden",
    "select_before_sample",
    "toy_backbone_hidden",
    "train_abstain_head",
]
