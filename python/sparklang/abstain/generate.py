"""Local generate with SELECT-before-SAMPLE abstain gate.

Uses a real head on last-token hidden states. Hidden sources
(priority): SPARK_ABSTAIN_HIDDEN file → HF forward (when
SPARK_ABSTAIN_HF=1) → best-effort vLLM URL. Never invents a
substitute as a live model answer.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, Optional, Union

os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")

import torch

from sparklang.abstain.attach import load_manifest
from sparklang.abstain.gate import GateConfig, select_before_sample
from sparklang.abstain.head import AbstainHead, load_head
from sparklang.abstain.inventable import outer_verify_or_refuse

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


def _hf_local_files_only(model_id: str) -> bool:
    """Prefer on-disk / offline — never surprise-download in CI."""
    if Path(model_id).exists():
        return True
    if os.environ.get("SPARK_ABSTAIN_HF_LOCAL_ONLY", "") == "1":
        return True
    if os.environ.get("TRANSFORMERS_OFFLINE", "") == "1":
        return True
    return False


def _load_hf_causal(model_id: str) -> Optional[tuple[Any, Any]]:
    """Load tokenizer + causal LM, or None if unavailable."""
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
    load_kw: dict[str, Any] = {}
    if _hf_local_files_only(model_id):
        load_kw["local_files_only"] = True
    try:
        tok = AutoTokenizer.from_pretrained(model_id, **load_kw)
        if tok.pad_token is None:
            tok.pad_token = tok.eos_token
        model = AutoModelForCausalLM.from_pretrained(
            model_id,
            torch_dtype=torch.float32,
            **load_kw,
        )
    except Exception:
        return None
    model.eval()
    return tok, model


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
    loaded = _load_hf_causal(model_id)
    if loaded is None:
        return None
    tok, model = loaded
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
    entropy: Optional[float] = None,
    margin: Optional[float] = None,
) -> Optional[dict[str, Any]]:
    """One HF load: prefill → SELECT → optional SAMPLE.

    Returns None if transformers / model load fails.
    """
    model_id = require_explicit_model(model_id)
    loaded = _load_hf_causal(model_id)
    if loaded is None:
        return None
    tok, model = loaded
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
    # Optional next-token entropy from logits when not provided.
    ent = entropy
    if ent is None and config.entropy_max is not None:
        logits = out.logits[0, -1, :].float()
        probs = torch.softmax(logits, dim=-1)
        ent = float(
            (-(probs * torch.log(probs.clamp_min(1e-12))).sum())
            .item()
        )
    p = score_hidden(head, hidden)
    d = select_before_sample(
        p, config, entropy=ent, margin=margin
    )
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
    timeout_s: Optional[float] = None,
    model: Optional[str] = None,
    token: Optional[str] = None,
) -> Optional[torch.Tensor]:
    """Best-effort ``/spark_hidden`` sidecar (vLLM-shaped) export.

    Contract: ``sparklang.abstain.spark_hidden``. Env::

      SPARK_ABSTAIN_VLLM_URL
      SPARK_ABSTAIN_VLLM_TIMEOUT  (default 30s)
      SPARK_ABSTAIN_VLLM_TOKEN    (optional Bearer)

    Returns None on any miss — never invents.
    """
    from sparklang.abstain.spark_hidden import post_spark_hidden

    packed = post_spark_hidden(
        base_url,
        prompt,
        model=model,
        timeout_s=timeout_s,
        token=token,
    )
    if packed is None:
        return None
    return torch.tensor(packed.hidden, dtype=torch.float32)


def _resolve_head_and_cfg(
    *,
    weights: Optional[str],
    manifest: Optional[str],
    threshold: Optional[float],
    idk: Optional[str],
    entropy_max: Optional[float] = None,
    margin_min: Optional[float] = None,
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
            entropy_max=(
                float(entropy_max)
                if entropy_max is not None
                else (
                    float(man["entropy_max"])
                    if man.get("entropy_max") is not None
                    else None
                )
            ),
            margin_min=(
                float(margin_min)
                if margin_min is not None
                else (
                    float(man["margin_min"])
                    if man.get("margin_min") is not None
                    else None
                )
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
        entropy_max=(
            float(entropy_max) if entropy_max is not None else None
        ),
        margin_min=(
            float(margin_min) if margin_min is not None else None
        ),
    )
    return head, cfg, man


def _env_float(name: str) -> Optional[float]:
    raw = os.environ.get(name)
    if raw is None or not str(raw).strip():
        return None
    return float(raw)


def _sample_via_openai(
    base_url: str,
    prompt: str,
    *,
    model: Optional[str] = None,
    max_new_tokens: int = 32,
    token: Optional[str] = None,
    timeout_s: float = 30.0,
) -> Optional[str]:
    """Best-effort OpenAI-compat chat SAMPLE after SELECT continue."""
    import json
    import urllib.error
    import urllib.request

    url = base_url.rstrip("/") + "/v1/chat/completions"
    body = {
        "model": model or "local",
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_new_tokens,
        "temperature": 0,
    }
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, OSError, ValueError):
        return None
    try:
        return str(
            payload["choices"][0]["message"]["content"]
        ).strip()
    except (KeyError, IndexError, TypeError):
        return None


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
    entropy_max: Optional[float] = None,
    margin_min: Optional[float] = None,
    entropy: Optional[float] = None,
    margin: Optional[float] = None,
    outer_verify: Optional[bool] = None,
    sot_ok: bool = False,
) -> dict[str, Any]:
    """Live gated ask — real p(abstain|h), no stub invent.

    Outer verify-or-refuse is **on by default**: inventable
    prompts without SoT emit IDK and halt (no SAMPLE). Pass
    ``outer_verify=False`` or ``SPARK_ABSTAIN_OUTER_VERIFY=0``
    to disable. ``SPARK_ABSTAIN_SOT_OK=1`` allows inventable
    through after a real SoT / expect.

    Env (when kwargs omitted)::

      SPARK_ABSTAIN_WEIGHTS / SPARK_ABSTAIN_MANIFEST
      SPARK_ABSTAIN_MODEL / SPARK_ABSTAIN_HIDDEN
      SPARK_ABSTAIN_HF=1  (allow hub id + HF forward)
      SPARK_ABSTAIN_VLLM_URL  (optional /spark_hidden sidecar)
      SPARK_ABSTAIN_VLLM_TIMEOUT / SPARK_ABSTAIN_VLLM_TOKEN
      SPARK_ABSTAIN_SAMPLE_URL  (OpenAI-compat SAMPLE after continue)
      SPARK_ABSTAIN_ENTROPY_MAX / SPARK_ABSTAIN_MARGIN_MIN
      SPARK_ABSTAIN_OUTER_VERIFY=0  (disable default outer refuse)
      SPARK_ABSTAIN_SOT_OK=1  (SoT already verified)
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
    sample_url = os.environ.get("SPARK_ABSTAIN_SAMPLE_URL") or None
    hf_on = os.environ.get("SPARK_ABSTAIN_HF", "") == "1"
    if entropy_max is None:
        entropy_max = _env_float("SPARK_ABSTAIN_ENTROPY_MAX")
    if margin_min is None:
        margin_min = _env_float("SPARK_ABSTAIN_MARGIN_MIN")
    env_ov = os.environ.get("SPARK_ABSTAIN_OUTER_VERIFY", "")
    if env_ov == "0":
        outer_verify = False
    elif outer_verify is None:
        outer_verify = True
    if os.environ.get("SPARK_ABSTAIN_SOT_OK", "") == "1":
        sot_ok = True

    if outer_verify:
        outer = outer_verify_or_refuse(
            prompt,
            sot_ok=sot_ok,
            idk=idk or "I don't know.",
        )
        if outer["abstain"]:
            outer["mode"] = "outer"
            return outer

    head, cfg, man = _resolve_head_and_cfg(
        weights=weights,
        manifest=manifest,
        threshold=threshold,
        idk=idk,
        entropy_max=entropy_max,
        margin_min=margin_min,
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
            entropy=entropy,
            margin=margin,
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
        hidden = try_vllm_last_hidden(
            vllm_url,
            prompt,
            model=model,
        )
        if hidden is not None:
            source = "vllm_spark_hidden"

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

    result = gated_from_hidden(
        head,
        hidden,
        cfg,
        continue_text="",
        entropy=entropy,
        margin=margin,
    )
    result["mode"] = "live"
    result["prompt"] = prompt
    result["hidden_source"] = source
    if model:
        result["model"] = model
    if result["abstain"]:
        return result
    # Continue: SAMPLE via OpenAI-compat if configured; else defer.
    if sample_url:
        cont = _sample_via_openai(
            sample_url,
            prompt,
            model=model,
            max_new_tokens=max_new_tokens,
            token=os.environ.get("SPARK_ABSTAIN_SAMPLE_TOKEN")
            or os.environ.get("SPARK_ABSTAIN_VLLM_TOKEN"),
        )
        if cont is not None:
            result["text"] = cont
            result["sample_source"] = "openai_compat"
            return result
    result["text"] = ""
    result["note"] = (
        "continue - SAMPLE deferred "
        "(provide HF model for in-process generate, "
        "or SPARK_ABSTAIN_SAMPLE_URL)"
    )
    return result