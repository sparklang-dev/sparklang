#!/usr/bin/env python3
"""HF last-token hidden export sidecar (``/spark_hidden``).

Stock vLLM OpenAI-compat does **not** return last-layer states.
Run this beside (or instead of) a chat server so
``SPARK_ABSTAIN_VLLM_URL`` can feed live ``head ask``.

Requires an **explicit** HF directory or hub id — never gateway
aliases (``auto`` / ``code`` / ``fast``).

Install::

  pip install -e 'python/[sidecar]'

Run::

  PYTHONPATH=python python3 \\
    tools/spark-abstain/spark_hidden_sidecar.py \\
    --model /path/to/hf-model --port 8765

  SPARK_ABSTAIN_VLLM_URL=http://127.0.0.1:8765 \\
    ./spark-abstain --live ask --prompt "…" \\
    --weights out/heads/abstain.pt

CI / no GPU: use ``spark_hidden_stub.py`` (toy vectors) instead.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any, Optional

_ROOT = Path(__file__).resolve().parents[2]
_PY = _ROOT / "python"
if _PY.is_dir() and str(_PY) not in sys.path:
    sys.path.insert(0, str(_PY))

os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")

from sparklang.abstain.generate import (  # noqa: E402
    require_explicit_model,
)
from sparklang.abstain.spark_hidden import (  # noqa: E402
    SparkHiddenContractError,
    build_response,
    parse_request,
)


class HiddenExporter:
    """Load one HF causal LM and export last-token hiddens."""

    def __init__(self, model_id: str) -> None:
        """Load tokenizer + model once (CPU by default)."""
        self.model_id = require_explicit_model(model_id)
        try:
            from transformers import (  # type: ignore
                AutoModelForCausalLM,
                AutoTokenizer,
            )
        except ImportError as exc:
            raise SystemExit(
                "spark_hidden_sidecar needs transformers — "
                "pip install -e 'python/[sidecar]'"
            ) from exc
        self._tok = AutoTokenizer.from_pretrained(self.model_id)
        if self._tok.pad_token is None:
            self._tok.pad_token = self._tok.eos_token
        import torch

        self._torch = torch
        self._model = AutoModelForCausalLM.from_pretrained(
            self.model_id,
            torch_dtype=torch.float32,
        )
        self._model.eval()

    def export(
        self,
        prompt: str,
        *,
        max_length: int = 512,
        layer: int = -1,
    ) -> dict[str, Any]:
        """Return contract JSON for one prompt."""
        inputs = self._tok(
            prompt,
            return_tensors="pt",
            truncation=True,
            max_length=max_length,
        )
        n_tok = int(inputs["input_ids"].shape[-1])
        with self._torch.no_grad():
            out = self._model(
                **inputs,
                output_hidden_states=True,
                use_cache=False,
            )
        hs = out.hidden_states
        if not hs:
            raise RuntimeError("model returned no hidden_states")
        idx = layer if layer >= 0 else len(hs) + layer
        if idx < 0 or idx >= len(hs):
            raise RuntimeError(f"layer {layer} out of range")
        vec = hs[idx][0, -1, :].detach().cpu().float()
        hidden = [float(x) for x in vec.tolist()]
        resp = build_response(
            hidden,
            model=self.model_id,
            source="hf_prefill",
            layer=layer,
            prompt_tokens=n_tok,
        )
        return resp.to_dict()


def create_app(exporter: HiddenExporter, *, token: Optional[str] = None):
    """Build a FastAPI app exposing ``/spark_hidden`` + ``/health``."""
    try:
        from fastapi import FastAPI, HTTPException, Request
        from fastapi.responses import JSONResponse
    except ImportError as exc:
        raise SystemExit(
            "spark_hidden_sidecar needs fastapi — "
            "pip install -e 'python/[sidecar]'"
        ) from exc

    app = FastAPI(
        title="SparkLang spark_hidden sidecar",
        version="1.0.0",
        docs_url=None,
        redoc_url=None,
    )
    bearer = (token or "").strip() or None

    def _check_auth(request: Request) -> None:
        if not bearer:
            return
        auth = request.headers.get("Authorization") or ""
        if auth != f"Bearer {bearer}":
            raise HTTPException(status_code=401, detail="unauthorized")

    @app.get("/health")
    def health() -> dict[str, Any]:
        return {
            "ok": True,
            "model": exporter.model_id,
            "object": "spark.hidden.health",
        }

    @app.post("/spark_hidden")
    async def spark_hidden(request: Request) -> JSONResponse:
        _check_auth(request)
        try:
            body = await request.json()
        except Exception as exc:
            raise HTTPException(
                status_code=400, detail="bad json"
            ) from exc
        try:
            req = parse_request(body)
        except SparkHiddenContractError as exc:
            raise HTTPException(
                status_code=400, detail=str(exc)
            ) from exc
        # Per-request model override refused unless identical —
        # sidecar serves one loaded backbone (no silent swap).
        if req.model and req.model != exporter.model_id:
            raise HTTPException(
                status_code=400,
                detail=(
                    "model override must match loaded "
                    f"{exporter.model_id!r} (or omit)"
                ),
            )
        try:
            payload = exporter.export(
                req.prompt,
                max_length=req.max_length,
                layer=req.layer,
            )
        except Exception as exc:
            raise HTTPException(
                status_code=500, detail=str(exc)
            ) from exc
        return JSONResponse(payload)

    return app


def main(argv: list[str] | None = None) -> int:
    """Run uvicorn on the HF ``/spark_hidden`` sidecar."""
    ap = argparse.ArgumentParser(prog="spark-hidden-sidecar")
    ap.add_argument(
        "--model",
        default=os.environ.get("SPARK_HIDDEN_MODEL")
        or os.environ.get("SPARK_ABSTAIN_MODEL")
        or "",
        help="explicit HF dir or hub org/name (required)",
    )
    ap.add_argument(
        "--host",
        default=os.environ.get("SPARK_HIDDEN_HOST", "127.0.0.1"),
    )
    ap.add_argument(
        "--port",
        type=int,
        default=int(os.environ.get("SPARK_HIDDEN_PORT", "8765")),
    )
    ap.add_argument(
        "--token",
        default=os.environ.get("SPARK_HIDDEN_TOKEN")
        or os.environ.get("SPARK_ABSTAIN_VLLM_TOKEN")
        or "",
        help="optional Bearer token (client: SPARK_ABSTAIN_VLLM_TOKEN)",
    )
    args = ap.parse_args(argv)
    if not str(args.model).strip():
        ap.error(
            "need --model / SPARK_HIDDEN_MODEL "
            "(explicit HF path or org/name)"
        )
    try:
        import uvicorn
    except ImportError as exc:
        raise SystemExit(
            "spark_hidden_sidecar needs uvicorn — "
            "pip install -e 'python/[sidecar]'"
        ) from exc

    exporter = HiddenExporter(str(args.model).strip())
    app = create_app(
        exporter,
        token=str(args.token).strip() or None,
    )
    print(
        json.dumps(
            {
                "op": "spark_hidden_sidecar",
                "listen": f"http://{args.host}:{args.port}",
                "path": "/spark_hidden",
                "model": exporter.model_id,
                "auth": bool(str(args.token).strip()),
            }
        ),
        flush=True,
    )
    uvicorn.run(
        app,
        host=str(args.host),
        port=int(args.port),
        log_level="info",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
