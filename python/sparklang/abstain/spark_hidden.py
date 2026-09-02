"""OpenAI-adjacent ``/spark_hidden`` contract + HTTP client.

Stock vLLM OpenAI-compat ``/v1/chat/completions`` does **not** export
last-layer states. SparkLang ask POSTs here instead:

  POST {base}/spark_hidden
  Content-Type: application/json
  Authorization: Bearer <optional>

Request::

  {"prompt": "...", "model": "optional/override",
   "max_length": 512, "layer": -1}

Response::

  {"object": "spark.hidden", "hidden": [float, ...], "dim": N,
   "model": "explicit-id", "source": "hf_prefill", "layer": -1,
   "prompt_tokens": 12}

Never invents vectors on the client — miss → ``None``.
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any, Optional

SPARK_HIDDEN_OBJECT = "spark.hidden"
DEFAULT_TIMEOUT_S = 30.0
DEFAULT_MAX_LENGTH = 512


@dataclass(frozen=True)
class SparkHiddenRequest:
    """Validated POST body for ``/spark_hidden``."""

    prompt: str
    model: Optional[str] = None
    max_length: int = DEFAULT_MAX_LENGTH
    layer: int = -1

    def to_dict(self) -> dict[str, Any]:
        """Serialize for JSON POST."""
        d: dict[str, Any] = {
            "prompt": self.prompt,
            "max_length": int(self.max_length),
            "layer": int(self.layer),
        }
        if self.model:
            d["model"] = self.model
        return d


@dataclass(frozen=True)
class SparkHiddenResponse:
    """Validated response from ``/spark_hidden``."""

    hidden: list[float]
    dim: int
    object: str = SPARK_HIDDEN_OBJECT
    model: Optional[str] = None
    source: Optional[str] = None
    layer: int = -1
    prompt_tokens: Optional[int] = None

    def to_dict(self) -> dict[str, Any]:
        """Serialize JSON body."""
        d: dict[str, Any] = {
            "object": self.object,
            "hidden": list(self.hidden),
            "dim": int(self.dim),
            "layer": int(self.layer),
        }
        if self.model is not None:
            d["model"] = self.model
        if self.source is not None:
            d["source"] = self.source
        if self.prompt_tokens is not None:
            d["prompt_tokens"] = int(self.prompt_tokens)
        return d


class SparkHiddenContractError(ValueError):
    """Request or response failed contract checks."""


def parse_request(body: Any) -> SparkHiddenRequest:
    """Parse and validate a JSON request body."""
    if not isinstance(body, dict):
        raise SparkHiddenContractError("body must be a JSON object")
    prompt = body.get("prompt")
    if not isinstance(prompt, str) or not prompt.strip():
        raise SparkHiddenContractError("need non-empty prompt")
    model = body.get("model")
    if model is not None and not isinstance(model, str):
        raise SparkHiddenContractError("model must be a string")
    if isinstance(model, str) and not model.strip():
        model = None
    max_length = body.get("max_length", DEFAULT_MAX_LENGTH)
    if not isinstance(max_length, int) or isinstance(max_length, bool):
        raise SparkHiddenContractError("max_length must be int")
    if max_length < 1 or max_length > 131072:
        raise SparkHiddenContractError("max_length out of range")
    layer = body.get("layer", -1)
    if not isinstance(layer, int) or isinstance(layer, bool):
        raise SparkHiddenContractError("layer must be int")
    return SparkHiddenRequest(
        prompt=prompt.strip(),
        model=model.strip() if isinstance(model, str) else None,
        max_length=max_length,
        layer=layer,
    )


def build_response(
    hidden: list[float],
    *,
    model: Optional[str] = None,
    source: Optional[str] = None,
    layer: int = -1,
    prompt_tokens: Optional[int] = None,
    object_name: str = SPARK_HIDDEN_OBJECT,
) -> SparkHiddenResponse:
    """Build a validated response from a float vector."""
    if not isinstance(hidden, list) or not hidden:
        raise SparkHiddenContractError("hidden must be non-empty list")
    floats: list[float] = []
    for x in hidden:
        if isinstance(x, bool) or not isinstance(x, (int, float)):
            raise SparkHiddenContractError("hidden must be floats")
        floats.append(float(x))
    return SparkHiddenResponse(
        hidden=floats,
        dim=len(floats),
        object=object_name,
        model=model,
        source=source,
        layer=layer,
        prompt_tokens=prompt_tokens,
    )


def parse_response(payload: Any) -> SparkHiddenResponse:
    """Parse and validate a JSON response body."""
    if not isinstance(payload, dict):
        raise SparkHiddenContractError("response must be a JSON object")
    feats = payload.get("hidden")
    if not isinstance(feats, list) or not feats:
        raise SparkHiddenContractError("missing hidden")
    floats: list[float] = []
    for x in feats:
        if isinstance(x, bool) or not isinstance(x, (int, float)):
            raise SparkHiddenContractError("hidden must be floats")
        floats.append(float(x))
    dim_raw = payload.get("dim")
    if dim_raw is not None:
        if not isinstance(dim_raw, int) or isinstance(dim_raw, bool):
            raise SparkHiddenContractError("dim must be int")
        if int(dim_raw) != len(floats):
            raise SparkHiddenContractError(
                f"dim {dim_raw} != len(hidden) {len(floats)}"
            )
    obj = payload.get("object", SPARK_HIDDEN_OBJECT)
    if obj is not None and not isinstance(obj, str):
        raise SparkHiddenContractError("object must be a string")
    model = payload.get("model")
    if model is not None and not isinstance(model, str):
        raise SparkHiddenContractError("model must be a string")
    source = payload.get("source")
    if source is not None and not isinstance(source, str):
        raise SparkHiddenContractError("source must be a string")
    layer = payload.get("layer", -1)
    if not isinstance(layer, int) or isinstance(layer, bool):
        raise SparkHiddenContractError("layer must be int")
    pt = payload.get("prompt_tokens")
    if pt is not None and (
        not isinstance(pt, int) or isinstance(pt, bool)
    ):
        raise SparkHiddenContractError("prompt_tokens must be int")
    return SparkHiddenResponse(
        hidden=floats,
        dim=len(floats),
        object=str(obj or SPARK_HIDDEN_OBJECT),
        model=model,
        source=source,
        layer=layer,
        prompt_tokens=pt,
    )


def post_spark_hidden(
    base_url: str,
    prompt: str,
    *,
    model: Optional[str] = None,
    max_length: int = DEFAULT_MAX_LENGTH,
    layer: int = -1,
    timeout_s: Optional[float] = None,
    token: Optional[str] = None,
) -> Optional[SparkHiddenResponse]:
    """POST ``/spark_hidden``; return None on any transport/contract miss.

    Env fallbacks (when kwargs omitted)::

      SPARK_ABSTAIN_VLLM_TIMEOUT  (seconds, default 30)
      SPARK_ABSTAIN_VLLM_TOKEN    (Bearer)
    """
    base = (base_url or "").strip()
    if not base:
        return None
    req = SparkHiddenRequest(
        prompt=prompt,
        model=model,
        max_length=max_length,
        layer=layer,
    )
    if timeout_s is None:
        raw_t = os.environ.get("SPARK_ABSTAIN_VLLM_TIMEOUT", "")
        try:
            timeout_s = float(raw_t) if raw_t else DEFAULT_TIMEOUT_S
        except ValueError:
            timeout_s = DEFAULT_TIMEOUT_S
    if token is None:
        token = os.environ.get("SPARK_ABSTAIN_VLLM_TOKEN") or None
    url = base.rstrip("/") + "/spark_hidden"
    body = json.dumps(req.to_dict()).encode("utf-8")
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    http_req = urllib.request.Request(
        url,
        data=body,
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(
            http_req, timeout=float(timeout_s)
        ) as resp:
            if int(getattr(resp, "status", 200) or 200) >= 300:
                return None
            raw = resp.read().decode("utf-8")
            payload = json.loads(raw)
    except (
        urllib.error.URLError,
        TimeoutError,
        ValueError,
        OSError,
        json.JSONDecodeError,
    ):
        return None
    try:
        return parse_response(payload)
    except SparkHiddenContractError:
        return None
