"""SELECT-before-SAMPLE abstain gate (pure Python; no GPU)."""

from __future__ import annotations

import argparse
import json
import math
from dataclasses import dataclass
from typing import Optional


@dataclass(frozen=True)
class GateConfig:
    """Threshold and optional entropy / margin trips."""

    threshold: float = 0.7
    idk: str = "I don't know."
    entropy_max: Optional[float] = None
    margin_min: Optional[float] = None


@dataclass(frozen=True)
class GateDecision:
    """Result of one SELECT step."""

    abstain: bool
    p_abstain: float
    text: Optional[str]
    halted: bool
    reason: str


def _sigmoid(x: float) -> float:
    if x >= 0:
        z = math.exp(-x)
        return 1.0 / (1.0 + z)
    z = math.exp(x)
    return z / (1.0 + z)


def select_before_sample(
    p_abstain: float,
    config: GateConfig,
    *,
    entropy: Optional[float] = None,
    margin: Optional[float] = None,
) -> GateDecision:
    """If gate fires → IDK + halt; else continue (caller samples)."""
    if not 0.0 <= p_abstain <= 1.0:
        raise ValueError("p_abstain must be in [0, 1]")
    if config.entropy_max is not None and entropy is not None:
        if entropy > config.entropy_max:
            return GateDecision(
                True, p_abstain, config.idk, True, "entropy"
            )
    if config.margin_min is not None and margin is not None:
        if margin < config.margin_min:
            return GateDecision(
                True, p_abstain, config.idk, True, "margin"
            )
    if p_abstain >= config.threshold:
        return GateDecision(
            True, p_abstain, config.idk, True, "threshold"
        )
    return GateDecision(False, p_abstain, None, False, "continue")


def logit_to_p(logit: float) -> float:
    """Map a raw abstain logit to probability."""
    return _sigmoid(logit)


def main(argv: Optional[list[str]] = None) -> int:
    """CLI: print gate decision JSON for a given p."""
    ap = argparse.ArgumentParser(description="Abstain gate check")
    ap.add_argument("--p", type=float, required=True)
    ap.add_argument("--threshold", type=float, default=0.7)
    ap.add_argument("--idk", default="I don't know.")
    ap.add_argument("--entropy", type=float, default=None)
    ap.add_argument("--entropy-max", type=float, default=None)
    ap.add_argument("--margin", type=float, default=None)
    ap.add_argument("--margin-min", type=float, default=None)
    args = ap.parse_args(argv)
    cfg = GateConfig(
        threshold=args.threshold,
        idk=args.idk,
        entropy_max=args.entropy_max,
        margin_min=args.margin_min,
    )
    d = select_before_sample(
        args.p,
        cfg,
        entropy=args.entropy,
        margin=args.margin,
    )
    print(
        json.dumps(
            {
                "abstain": d.abstain,
                "p_abstain": d.p_abstain,
                "text": d.text,
                "halted": d.halted,
                "reason": d.reason,
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
