#!/usr/bin/env python3
"""Minimal /spark_hidden stub for local abstain verify (toy vectors).

Not vLLM. Stock OpenAI-compat servers do not export last-layer
hiddens — this stub matches the SparkLang contract so CI / laptop
can exercise ``SPARK_ABSTAIN_VLLM_URL`` without a 27B.

  PYTHONPATH=python python3 tools/spark-abstain/spark_hidden_stub.py \\
    --port 8765 --dim 16
  SPARK_ABSTAIN_VLLM_URL=http://127.0.0.1:8765 \\
    ./spark-abstain --live ask --prompt "…" --weights …
"""

from __future__ import annotations

import argparse
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import sys

_ROOT = Path(__file__).resolve().parents[2]
_PY = _ROOT / "python"
if _PY.is_dir() and str(_PY) not in sys.path:
    sys.path.insert(0, str(_PY))

from sparklang.abstain.export import toy_backbone_hidden  # noqa: E402


def main(argv: list[str] | None = None) -> int:
    """Serve POST /spark_hidden with toy last-token vectors."""
    ap = argparse.ArgumentParser(
        prog="spark-hidden-stub",
    )
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--dim", type=int, default=16)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args(argv)
    dim = int(args.dim)
    seed = int(args.seed)

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt: str, *a: object) -> None:
            sys.stderr.write(
                "%s - %s\n" % (self.address_string(), fmt % a)
            )

        def do_POST(self) -> None:  # noqa: N802
            if self.path.rstrip("/") != "/spark_hidden":
                self.send_error(404, "use POST /spark_hidden")
                return
            n = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(n) if n else b"{}"
            try:
                body = json.loads(raw.decode("utf-8") or "{}")
            except json.JSONDecodeError:
                self.send_error(400, "bad json")
                return
            prompt = str(body.get("prompt") or "")
            if not prompt:
                self.send_error(400, "need prompt")
                return
            hidden = toy_backbone_hidden(
                prompt, dim, seed=seed
            )
            payload = {
                "hidden": hidden,
                "dim": dim,
                "source": "toy_stub",
            }
            data = json.dumps(payload).encode("utf-8")
            self.send_response(200)
            self.send_header(
                "Content-Type", "application/json"
            )
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    httpd = HTTPServer((args.host, args.port), Handler)
    print(
        f"spark_hidden stub on "
        f"http://{args.host}:{args.port}/spark_hidden "
        f"dim={dim}",
        flush=True,
    )
    httpd.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
