"""Local generate with SELECT-before-SAMPLE abstain gate.

Uses a real head on last-token hidden states. Hidden sources
(priority): SPARK_ABSTAIN_HIDDEN file → HF forward (when
SPARK_ABSTAIN_HF=1) → best-effort vLLM URL. Never invents a
substitute as a live model answer.
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Optional, Union

os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")

import torch

from sparklang.abstain.attach import load_manifest
from sparklang.abstain.gate import GateConfig, select_before_sample
from sparklang.abstain.head import AbstainHead, load_head

PathLike = Union[str, Path]

# Gateway-style short names — never treat as an HF model id.
_GATEWAY_ALIAS_NAMES = frozenset(
    {
        "auto",
        "fast",
        "code",
        "best",
        "code-bulk",
        "code-hard",
        "code-max",
        "code-open",
        "embed",
        "embed-rag",
        "local-big",
        "voice",
        "voice-prod",
        "alias-code",
        "gemini-flash",
        "luna",
    }
)


def require_explicit_model(model_id: str) -> str:
    """Refuse gateway alias names; require path or org/name HF id."""
    mid = model_id.strip()
    if not mid:
        raise SystemExit("model id empty")
    if mid.lower() in _GATEWAY_ALIAS_NAMES:
        raise SystemExit(
            f"refuse gateway alias {mid!r} — pass a local "
            "HF directory or explicit hub id (org/name), "
            "not auto/code/fast"
        )
    return mid


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
    """SELECT: abstain → IDK; else return continue_text."""
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


def load_hidden_tensor(path: PathLike) -> torch.Tensor:
    """Load last-token hidden from .pt/.pth or JSON float list."""
    p = Path(path)
    if not p.is_file():
        raise FileNotFoundError(f"hidden missing: {p}")
    if p.suffix.lower() in (".json", ".txt"):
        data = json.loads(p.read_text(encoding="utf-8"))
        if isinstance(data, dict):
            data = data.get("hidden") or data.get("features")
        t = torch.tensor(data, dtype=torch.float32)
    else:
        obj = torch.load(p, map_location="cpu", weights_only=False)
        if isinstance(obj, torch.Tensor):
            t = obj.float()
        elif isinstance(obj, dict) and "hidden" in obj:
            t = torch.as_tensor(obj["hidden"]).float()
        else:
            raise ValueError(f"bad hidden file: {p}")
    if t.dim() > 1:
        t = t.reshape(-1)
    return t.detach().cpu()


def try_hf_last_hidden(
    model_id: str,
    prompt: str,
    *,
    max_length: int = 512,
) -> Optional[torch.Tensor]:
    """HF causal-LM prefill → last-token last-layer hidden.

    Returns None if transformers / weights unavailable.
    """
    model_id = require_explicit_model(model_id)
    try:
        from transformers import (  # type: ignore
            AutoModelForCausalLM,
            AutoTokenizer,
        )
    except ImportError:
        return None
    path = Path(model_id)
    # Local dir always OK; hub ids need SPARK_ABSTAIN_HF=1.
    if not path.exists():
        if os.environ.get("SPARK_ABSTAIN_HF", "") != "1":
            return None
        if "/" not in model_id:
            return None
    try:
        tok = AutoTokenizer.from_pretrained(model_id)
        if tok.pad_token is None:
            tok.pad_token = tok.eos_token
        model = AutoModelForCausalLM.from_pretrained(
            model_id,
            torch_dtype=torch.float32,
        )
    except Exception:
        return None
    model.eval()
    inputs = tok(
        prompt,
        return_tensors="pt",
        truncation=True,
        max_length=max_length,
    )
    with torch.no_grad():
        out = model(
            **inputs,
            output_hidden_states=True,
            use_cache=False,
        )
    hs = out.hidden_states[-1]
    return hs[0, -1, :].detach().cpu().float()


def try_hf_select_then_sample(
    model_id: str,
    prompt: str,
    head: AbstainHead,
    config: GateConfig,
    *,
    max_new_tokens: int = 32,
    max_length: int = 512,
) -> Optional[dict[str, Any]]:
    """One HF load: prefill → SELECT → optional SAMPLE.

    Returns None if transformers / model load fails.
    """
    model_id = require_explicit_model(model_id)
    try:
        from transformers import (  # type: ignore
            AutoModelForCausalLM,
            AutoTokenizer,
        )
    except ImportError:
        return None
    path = Path(model_id)
    if not path.exists():
        if os.environ.get("SPARK_ABSTAIN_HF", "") != "1":
            return None
        if "/" not in model_id:
            return None
    try:
        tok = AutoTokenizer.from_pretrained(model_id)
        if tok.pad_token is None:
            tok.pad_token = tok.eos_token
        model = AutoModelForCausalLM.from_pretrained(
            model_id,
            torch_dtype=torch.float32,
        )
    except Exception:
        return None
    model.eval()
    inputs = tok(
        prompt,
        return_tensors="pt",
        truncation=True,
        max_length=max_length,
    )
    with torch.no_grad():
        out = model(
            **inputs,
            output_hidden_states=True,
            use_cache=True,
        )
    hidden = out.hidden_states[-1][0, -1, :].detach().cpu()
    # Dim mismatch: refuse rather than silent pad/truncate invent.
    if int(hidden.numel()) != int(head.hidden_dim):
        return {
            "op": "head_ask",
            "mode": "live-hf",
            "abstain": False,
            "halted": True,
            "p_abstain": None,
            "reason": "hidden_dim_mismatch",
            "text": "",
            "error": (
                f"head dim {head.hidden_dim} != "
                f"model hidden {int(hidden.numel())}"
            ),
            "prompt": prompt,
            "model": model_id,
        }
    p = score_hidden(head, hidden)
    d = select_before_sample(p, config)
    if d.abstain:
        return {
            "op": "head_ask",
            "mode": "live-hf",
            "abstain": True,
            "halted": True,
            "p_abstain": d.p_abstain,
            "reason": d.reason,
            "text": d.text,
            "prompt": prompt,
            "model": model_id,
            "hidden_source": "hf_prefill",
        }
    with torch.no_grad():
        gen = model.generate(
            **inputs,
            max_new_tokens=max_new_tokens,
            do_sample=False,
            pad_token_id=tok.pad_token_id,
        )
    new_tokens = gen[0, inputs["input_ids"].shape[-1] :]
    cont = tok.decode(new_tokens, skip_special_tokens=True)
    return {
        "op": "head_ask",
        "mode": "live-hf",
        "abstain": False,
        "halted": False,
        "p_abstain": d.p_abstain,
        "reason": "continue",
        "text": cont.strip(),
        "prompt": prompt,
        "model": model_id,
        "hidden_source": "hf_prefill",
    }


def try_vllm_last_hidden(
    base_url: str,
    prompt: str,
    *,
    timeout_s: float = 5.0,
) -> Optional[torch.Tensor]:
    """Best-effort vLLM sidecar hidden export.

    Expects POST ``{base}/spark_hidden`` JSON
    ``{"prompt": "..."}`` → ``{"hidden": [float, ...]}``.
    Returns None on any miss — never invents.
    """
    url = base_url.rstrip("/") + "/spark_hidden"
    body = json.dumps({"prompt": prompt}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, ValueError, OSError):
        return None
    feats = payload.get("hidden") if isinstance(payload, dict) else None
    if not isinstance(feats, list) or not feats:
        return None
    return torch.tensor(feats, dtype=torch.float32)


def _resolve_head_and_cfg(
    *,
    weights: Optional[str],
    manifest: Optional[str],
    threshold: Optional[float],
    idk: Optional[str],
) -> tuple[AbstainHead, GateConfig, dict[str, Any]]:
    """Load head from manifest or weights path."""
    man: dict[str, Any] = {}
    if manifest:
        man = load_manifest(manifest)
        w = str(man.get("weights") or weights or "")
        if not w:
            raise SystemExit("manifest missing weights")
        head = load_head(w)
        cfg = GateConfig(
            threshold=float(
                threshold
                if threshold is not None
                else man.get("threshold") or 0.7
            ),
            idk=str(
                idk
                if idk is not None
                else man.get("idk") or "I don't know."
            ),
        )
        return head, cfg, man
    if not weights:
        raise SystemExit(
            "head ask live needs --weights or "
            "SPARK_ABSTAIN_WEIGHTS / SPARK_ABSTAIN_MANIFEST"
        )
    head = load_head(weights)
    cfg = GateConfig(
        threshold=float(threshold if threshold is not None else 0.7),
        idk=str(idk if idk is not None else "I don't know."),
    )
    return head, cfg, man


def live_ask(
    prompt: str,
    *,
    weights: Optional[str] = None,
    manifest: Optional[str] = None,
    model: Optional[str] = None,
    hidden_path: Optional[str] = None,
    threshold: Optional[float] = None,
    idk: Optional[str] = None,
    max_new_tokens: int = 32,
) -> dict[str, Any]:
    """Live gated ask — real p(abstain|h), no stub invent.

    Env (when kwargs omitted)::

      SPARK_ABSTAIN_WEIGHTS / SPARK_ABSTAIN_MANIFEST
      SPARK_ABSTAIN_MODEL / SPARK_ABSTAIN_HIDDEN
      SPARK_ABSTAIN_HF=1  (allow hub id + HF forward)
      SPARK_ABSTAIN_VLLM_URL  (optional /spark_hidden)
    """
    weights = weights or os.environ.get("SPARK_ABSTAIN_WEIGHTS") or None
    manifest = (
        manifest or os.environ.get("SPARK_ABSTAIN_MANIFEST") or None
    )
    model = model or os.environ.get("SPARK_ABSTAIN_MODEL") or None
    hidden_path = (
        hidden_path or os.environ.get("SPARK_ABSTAIN_HIDDEN") or None
    )
    vllm_url = os.environ.get("SPARK_ABSTAIN_VLLM_URL") or None
    hf_on = os.environ.get("SPARK_ABSTAIN_HF", "") == "1"

    head, cfg, man = _resolve_head_and_cfg(
        weights=weights,
        manifest=manifest,
        threshold=threshold,
        idk=idk,
    )
    if not model and man.get("model"):
        model = str(man["model"])
    if model:
        model = require_explicit_model(model)

    # Preferred: one-shot HF SELECT then SAMPLE (same load).
    if model and (hf_on or Path(model).exists()) and not hidden_path:
        packed = try_hf_select_then_sample(
            model,
            prompt,
            head,
            cfg,
            max_new_tokens=max_new_tokens,
        )
        if packed is not None:
            return packed

    hidden: Optional[torch.Tensor] = None
    source = ""
    if hidden_path:
        hidden = load_hidden_tensor(hidden_path)
        source = "file"
    if hidden is None and model and (hf_on or Path(model).exists()):
        hidden = try_hf_last_hidden(model, prompt)
        if hidden is not None:
            source = "hf_prefill"
    if hidden is None and vllm_url:
        hidden = try_vllm_last_hidden(vllm_url, prompt)
        if hidden is not None:
            source = "vllm"

    if hidden is None:
        raise SystemExit(
            "head ask live: no hidden (set SPARK_ABSTAIN_HIDDEN, "
            "or SPARK_ABSTAIN_HF=1 + SPARK_ABSTAIN_MODEL, "
            "or SPARK_ABSTAIN_VLLM_URL; "
            "or SPARK_ABSTAIN_STUB=1 for fixture gate)"
        )

    if int(hidden.numel()) != int(head.hidden_dim):
        return {
            "op": "head_ask",
            "mode": "live",
            "abstain": False,
            "halted": True,
            "p_abstain": None,
            "reason": "hidden_dim_mismatch",
            "text": "",
            "error": (
                f"head dim {head.hidden_dim} != "
                f"hidden {int(hidden.numel())}"
            ),
            "prompt": prompt,
            "hidden_source": source,
        }

    result = gated_from_hidden(head, hidden, cfg, continue_text="")
    result["mode"] = "live"
    result["prompt"] = prompt
    result["hidden_source"] = source
    if model:
        result["model"] = model
    if not result["abstain"]:
        result["text"] = ""
        result["note"] = (
            "continue - SAMPLE deferred "
            "(provide HF model for in-process generate)"
        )
    return result
