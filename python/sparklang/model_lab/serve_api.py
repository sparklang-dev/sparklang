"""Tiny local serve API over existing CPU forward (G-lane).

HTTP or stdio JSON: predict next-token / embeddings from Spark
safetensors. Wraps ``run_tiny_forward`` / ``run_tiny_embed`` — no
attention math of its own. CPU only. Never the voice GPU / 6000.
Not a production LLM.
"""

from __future__ import annotations

import argparse
import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from sparklang import __version__ as SPARK_VERSION
from sparklang.model_lab.serve import run_tiny_embed, run_tiny_forward
from sparklang.model_lab.weights import read_safetensors

_PREFIX = "/v1"


def _token_ids_from_req(req: dict[str, Any]) -> list[int]:
    """Accept token_ids list or UTF-8 text as byte ids."""
    if "token_ids" in req and req["token_ids"] is not None:
        raw = req["token_ids"]
        if not isinstance(raw, list) or not raw:
            raise ValueError("token_ids must be a non-empty list")
        return [int(x) for x in raw]
    text = req.get("text")
    if isinstance(text, str) and text:
        return list(text.encode("utf-8"))
    raise ValueError("need token_ids or non-empty text")


class ServeEngine:
    """Load weights once; answer predict / embed / health / version."""

    def __init__(self, weights_path: str | Path) -> None:
        """Load Spark safetensors into memory (CPU)."""
        self.weights_path = Path(weights_path)
        if not self.weights_path.is_file():
            raise FileNotFoundError(
                "weights not found: %s" % self.weights_path
            )
        self.meta, self.tensors = read_safetensors(self.weights_path)
        self._lock = threading.Lock()

    def health(self) -> dict[str, Any]:
        """Liveness payload."""
        return {
            "ok": True,
            "mode": "cpu-forward",
            "production": False,
            "weights": str(self.weights_path),
        }

    def version(self) -> dict[str, Any]:
        """Version + lane identity."""
        return {
            "product": "sparklang",
            "version": SPARK_VERSION,
            "lane": "G",
            "mode": "cpu-forward",
            "production": False,
            "gpu": False,
        }

    def predict(self, req: dict[str, Any]) -> dict[str, Any]:
        """Next-token argmax via existing tiny CPU forward."""
        ids = _token_ids_from_req(req)
        with self._lock:
            fwd = run_tiny_forward(self.tensors, ids)
        return {
            "op": "predict",
            "mode": "cpu-forward",
            "production": False,
            "next_token": fwd["argmax"],
            "argmax": fwd["argmax"],
            "logit_max": fwd["logit_max"],
            "logits_preview": fwd["logits_preview"],
            "token_ids": fwd["token_ids"],
            "vocab": fwd["vocab"],
            "hidden_dim": fwd["hidden_dim"],
            "mlp0": fwd["mlp0"],
            "path": fwd["path"],
        }

    def embed(self, req: dict[str, Any]) -> dict[str, Any]:
        """Embedding vector via shared hidden path (no lm_head)."""
        ids = _token_ids_from_req(req)
        with self._lock:
            emb = run_tiny_embed(self.tensors, ids)
        return {
            "op": "embeddings",
            "mode": "cpu-forward",
            "production": False,
            "embedding": emb["embedding"],
            "token_ids": emb["token_ids"],
            "vocab": emb["vocab"],
            "hidden_dim": emb["hidden_dim"],
            "mlp0": emb["mlp0"],
            "path": emb["path"],
        }

    def handle(self, op: str, req: dict[str, Any]) -> dict[str, Any]:
        """Dispatch one JSON op (stdio or internal)."""
        key = (op or "").strip().lower()
        if key in ("health", "ping"):
            return self.health()
        if key in ("version", "ver"):
            return self.version()
        if key in ("predict", "next_token", "forward"):
            return self.predict(req)
        if key in ("embed", "embeddings", "embedding"):
            return self.embed(req)
        raise ValueError("unknown op: %s" % op)


def _send_json(
    handler: BaseHTTPRequestHandler,
    code: int,
    obj: dict[str, Any],
) -> None:
    body = (json.dumps(obj) + "\n").encode("utf-8")
    handler.send_response(code)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def _read_json(handler: BaseHTTPRequestHandler) -> dict[str, Any]:
    length = int(handler.headers.get("Content-Length", "0") or "0")
    raw = handler.rfile.read(length) if length else b"{}"
    return json.loads(raw.decode("utf-8") or "{}")


def make_handler(engine: ServeEngine) -> type[BaseHTTPRequestHandler]:
    """Build a request handler closed over ``engine``."""

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt: str, *args: Any) -> None:
            print(
                "[spark-serve-api] %s %s"
                % (self.address_string(), fmt % args)
            )

        def do_GET(self) -> None:  # noqa: N802
            path = urlparse(self.path).path.rstrip("/") or "/"
            try:
                if path in ("/health", "/v1/health"):
                    _send_json(self, 200, engine.health())
                    return
                if path in ("/version", "/v1/version"):
                    _send_json(self, 200, engine.version())
                    return
                _send_json(
                    self,
                    404,
                    {"error": "not_found", "path": path},
                )
            except (OSError, ValueError, KeyError) as exc:
                _send_json(
                    self,
                    500,
                    {"error": "server", "detail": str(exc)},
                )

        def do_POST(self) -> None:  # noqa: N802
            path = urlparse(self.path).path.rstrip("/") or "/"
            try:
                req = _read_json(self)
                if path in (
                    f"{_PREFIX}/predict",
                    "/predict",
                ):
                    _send_json(self, 200, engine.predict(req))
                    return
                if path in (
                    f"{_PREFIX}/embeddings",
                    "/embeddings",
                    f"{_PREFIX}/embed",
                    "/embed",
                ):
                    _send_json(self, 200, engine.embed(req))
                    return
                _send_json(
                    self,
                    404,
                    {"error": "not_found", "path": path},
                )
            except ValueError as exc:
                _send_json(
                    self,
                    400,
                    {"error": "bad_request", "detail": str(exc)},
                )
            except (OSError, KeyError, json.JSONDecodeError) as exc:
                _send_json(
                    self,
                    500,
                    {"error": "server", "detail": str(exc)},
                )

    return Handler


def serve_http(
    engine: ServeEngine,
    host: str = "127.0.0.1",
    port: int = 8765,
) -> None:
    """Run ThreadingHTTPServer until KeyboardInterrupt."""
    handler = make_handler(engine)
    httpd = ThreadingHTTPServer((host, port), handler)
    print(
        "[spark-serve-api] listening http://%s:%d "
        "(CPU; not production)" % (host, port),
        flush=True,
    )
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[spark-serve-api] stop", flush=True)
    finally:
        httpd.server_close()


def serve_stdio(engine: ServeEngine) -> int:
    """One JSON object per line on stdin → stdout."""
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
            if not isinstance(req, dict):
                raise ValueError("request must be a JSON object")
            op = str(req.get("op") or req.get("method") or "")
            out = engine.handle(op, req)
            sys.stdout.write(json.dumps(out) + "\n")
            sys.stdout.flush()
        except (ValueError, KeyError, json.JSONDecodeError) as exc:
            err = {"error": "bad_request", "detail": str(exc)}
            sys.stdout.write(json.dumps(err) + "\n")
            sys.stdout.flush()
    return 0


def main(argv: list[str] | None = None) -> int:
    """CLI: --http or --stdio over checkpoint safetensors."""
    p = argparse.ArgumentParser(
        description=(
            "Spark tiny CPU serve API (predict / embeddings). "
            "Not production. Never 6000."
        )
    )
    p.add_argument(
        "--weights",
        required=True,
        help="path to Spark weights.safetensors",
    )
    mode = p.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--http",
        action="store_true",
        help="serve HTTP on --host/--port",
    )
    mode.add_argument(
        "--stdio",
        action="store_true",
        help="line-oriented JSON on stdin/stdout",
    )
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=8765)
    args = p.parse_args(argv)
    engine = ServeEngine(args.weights)
    if args.stdio:
        return serve_stdio(engine)
    serve_http(engine, host=args.host, port=args.port)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
