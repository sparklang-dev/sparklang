"""Local generate with SELECT-before-SAMPLE abstain gate.

Uses stub or real head on provided hidden states. Optional HF path
when transformers + model weights are present — never invents.
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Optional, Union

os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")

import torch

from sparklang.abstain.attach import load_manifest
from sparklang.abstain.gate import GateConfig, select_before_sample
from sparklang.abstain.head import AbstainHead, load_head

PathLike = Union[str, Path]


def score_hidden(
    head: AbstainHead,
    hidden: torch.Tensor,
) -> float:
    """Return p(abstain) for one hidden vector."""
    head.eval()
    with torch.no_grad():
        p = head.p_abstain(hidden.float().cpu())
    return float(p.item() if p.ndim == 0 else p[0].item())


def gated_from_hidden(
    head: AbstainHead,
    hidden: torch.Tensor,
    config: GateConfig,
    *,
    continue_text: str = "",
    entropy: Optional[float] = None,
    margin: Optional[float] = None,
) -> dict[str, Any]:
    """SELECT: abstain → IDK; else return continue_text (caller sampled)."""
    p = score_hidden(head, hidden)
    d = select_before_sample(
        p, config, entropy=entropy, margin=margin
    )
    return {
        "op": "head_ask",
        "abstain": d.abstain,
        "halted": d.halted,
        "p_abstain": d.p_abstain,
        "reason": d.reason,
        "text": d.text if d.abstain else continue_text,
    }


def gated_from_manifest(
    manifest_path: PathLike,
    hidden: torch.Tensor,
    *,
    continue_text: str = "",
) -> dict[str, Any]:
    """Load attach manifest + head, then gate."""
    man = load_manifest(manifest_path)
    head = load_head(man["weights"])
    cfg = GateConfig(
        threshold=float(man.get("threshold") or 0.7),
        idk=str(man.get("idk") or "I don't know."),
    )
    return gated_from_hidden(
        head, hidden, cfg, continue_text=continue_text
    )


def try_hf_last_hidden(
    model_id: str,
    prompt: str,
    *,
    max_new_tokens: int = 16,
) -> Optional[torch.Tensor]:
    """Best-effort HF forward for last-token hidden (optional).

    Returns None if transformers / weights unavailable — callers
    must not invent a substitute as a real model answer.
    """
    try:
        from transformers import AutoModelForCausalLM, AutoTokenizer
    except ImportError:
        return None
    path = Path(model_id)
    if not path.exists() and "/" not in model_id:
        return None
    try:
        tok = AutoTokenizer.from_pretrained(model_id)
        model = AutoModelForCausalLM.from_pretrained(model_id)
    except Exception:
        return None
    model.eval()
    inputs = tok(prompt, return_tensors="pt")
    with torch.no_grad():
        out = model(
            **inputs,
            output_hidden_states=True,
            use_cache=False,
        )
    hs = out.hidden_states[-1]
    return hs[0, -1, :].detach().cpu()
