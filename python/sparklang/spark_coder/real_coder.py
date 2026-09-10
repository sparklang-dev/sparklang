"""Product coder lane — self-hosted Qwen3-Coder-30B on this box.

The product code model is a real 30B served locally by vLLM
(OpenAI-compatible, unit ``vllm-qwen3-coder-30b``, RTX 5090).
Offline / self-hosted: no API keys, no vendor calls.

This module only *consumes* the endpoint. It never starts, stops,
or restarts any service. When the endpoint is down, callers get a
plain ``ok: False`` result and CLI commands exit nonzero.

The in-repo TinyCoder (``model.py`` / ``train.py``) stays as the
reference implementation for the training pipeline; it is not the
product coder.
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from typing import Any

DEFAULT_ENDPOINT = "http://127.0.0.1:8003"
ENV_URL = "SPARK_CODER_URL"

# Factual identity of the serving unit (for messages only; this
# module never manages services).
SERVICE_HINT = "vLLM unit vllm-qwen3-coder-30b (RTX 5090)"


def endpoint_url(override: str | None = None) -> str:
    """Resolve the coder endpoint URL (flag > env > default)."""
    raw = (override or os.environ.get(ENV_URL) or "").strip()
    if not raw:
        raw = DEFAULT_ENDPOINT
    return raw.rstrip("/")


def _http_json(
    method: str,
    url: str,
    payload: dict[str, Any] | None,
    timeout: float,
) -> dict[str, Any]:
    """One JSON HTTP round-trip; raises on transport/HTTP error."""
    data = None
    headers = {"Content-Type": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url, data=data, headers=headers, method=method
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _down_result(url: str, detail: str) -> dict[str, Any]:
    """Plain 'endpoint down' result — never fake a completion."""
    return {
        "ok": False,
        "error": "coder_endpoint_down",
        "endpoint": url,
        "detail": detail,
        "hint": (
            "self-hosted coder endpoint is not serving at %s "
            "(%s); this repo never starts or stops services"
            % (url, SERVICE_HINT)
        ),
    }


def probe_endpoint(
    url: str | None = None, *, timeout: float = 5.0
) -> dict[str, Any]:
    """GET /v1/models — is the self-hosted coder serving?"""
    base = endpoint_url(url)
    try:
        body = _http_json("GET", base + "/v1/models", None, timeout)
    except (urllib.error.URLError, OSError, ValueError) as exc:
        return _down_result(base, str(exc))
    models = body.get("data") or []
    model_id = ""
    if models and isinstance(models[0], dict):
        model_id = str(models[0].get("id") or "")
    return {
        "ok": True,
        "endpoint": base,
        "model": model_id,
        "n_models": len(models),
    }


def generate(
    prompt: str,
    *,
    url: str | None = None,
    system: str | None = None,
    max_tokens: int = 512,
    temperature: float = 0.0,
    timeout: float = 120.0,
) -> dict[str, Any]:
    """Chat-complete ``prompt`` against the self-hosted 30B coder.

    Returns ``ok: False`` with a plain reason when the endpoint is
    down or errors; never fabricates a completion.
    """
    base = endpoint_url(url)
    probe = probe_endpoint(base, timeout=min(5.0, timeout))
    if not probe.get("ok"):
        return probe
    model = str(probe.get("model") or "")
    if not model:
        return {
            "ok": False,
            "error": "coder_endpoint_no_model",
            "endpoint": base,
            "detail": "/v1/models returned no model id",
        }
    messages: list[dict[str, str]] = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})
    payload = {
        "model": model,
        "messages": messages,
        "max_tokens": int(max_tokens),
        "temperature": float(temperature),
    }
    try:
        body = _http_json(
            "POST",
            base + "/v1/chat/completions",
            payload,
            timeout,
        )
    except (urllib.error.URLError, OSError, ValueError) as exc:
        return _down_result(base, str(exc))
    choices = body.get("choices") or []
    text = ""
    if choices and isinstance(choices[0], dict):
        msg = choices[0].get("message") or {}
        text = str(msg.get("content") or "")
    usage = body.get("usage") or {}
    return {
        "ok": True,
        "endpoint": base,
        "model": model,
        "prompt": prompt,
        "completion": text,
        "usage": {
            "prompt_tokens": int(usage.get("prompt_tokens") or 0),
            "completion_tokens": int(
                usage.get("completion_tokens") or 0
            ),
        },
        "engine": "self-hosted-30b",
        "device": "rtx-5090",
        "never": "rtx-pro-6000",
    }
