#!/usr/bin/env python3
"""Reference local HTTP server for serve-helper (ranker / reply / router).

Modes:
  shadow — log beside a live turn; do not return helper output as primary
  live   — return helper ranking / reply selection

CPU only. Synthetic helpers. No vendor names.
"""

from __future__ import annotations

import argparse
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

SHADOW_LOG: list[dict[str, Any]] = []
LOCK = threading.Lock()
STATE: dict[str, Any] = {
    "helper": "",
    "as_name": "ranker",
    "mode": "shadow",
}


def _json_body(handler: BaseHTTPRequestHandler) -> dict[str, Any]:
    length = int(handler.headers.get("Content-Length", "0") or "0")
    raw = handler.rfile.read(length) if length else b"{}"
    return json.loads(raw.decode("utf-8") or "{}")


def _send(handler: BaseHTTPRequestHandler, code: int, obj: dict[str, Any]) -> None:
    body = (json.dumps(obj, separators=(",", ":")) + "\n").encode("utf-8")
    handler.send_response(code)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def _helper_payload(turn: str) -> dict[str, Any]:
    """Rank / select from helper dir artifacts (CPU heuristic)."""
    helper = Path(str(STATE["helper"]))
    kind = str(STATE["as_name"])
    score = 0.5
    if helper.is_dir():
        names = {p.name for p in helper.iterdir()}
        if "ranker.pt" in names or "pref_pack.json" in names:
            score = 0.82
            kind = "ranker"
        elif "router.pt" in names or "playbooks.json" in names:
            score = 0.78
            kind = "router"
        elif "replies.json" in names:
            score = 0.8
            kind = "reply"
        elif "ARTIFACT" in names:
            score = 0.7
    return {
        "helper": str(helper),
        "as": kind,
        "turn": turn,
        "score": score,
        "selected": turn[:120],
    }


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"[spark-serve-ref] {self.address_string()} {fmt % args}")

    def do_GET(self) -> None:  # noqa: N802
        path = urlparse(self.path).path.rstrip("/") or "/"
        if path in ("/", "/health", "/v1"):
            _send(
                self,
                200,
                {
                    "ok": True,
                    "service": "spark-serve-ref",
                    "helper": STATE["helper"],
                    "as": STATE["as_name"],
                    "mode": STATE["mode"],
                },
            )
            return
        if path == "/v1/shadow-log":
            with LOCK:
                rows = list(SHADOW_LOG[-50:])
            _send(self, 200, {"log": rows, "n": len(rows)})
            return
        _send(self, 404, {"error": "not_found", "path": path})

    def do_POST(self) -> None:  # noqa: N802
        path = urlparse(self.path).path.rstrip("/") or "/"
        req = _json_body(self)
        turn = str(req.get("turn") or req.get("text") or "")
        if path in ("/v1/turn", "/turn", "/v1/rank"):
            payload = _helper_payload(turn)
            mode = str(STATE["mode"])
            rec = {
                "ts": int(time.time()),
                "mode": mode,
                "request": req,
                "helper": payload,
            }
            with LOCK:
                SHADOW_LOG.append(rec)
            if mode == "shadow":
                _send(
                    self,
                    200,
                    {
                        "op": "serve",
                        "mode": "shadow",
                        "logged": True,
                        "primary": turn,
                        "shadow": payload,
                        "note": "shadow — helper logged, not returned as primary",
                    },
                )
                return
            _send(
                self,
                200,
                {
                    "op": "serve",
                    "mode": "live",
                    "result": payload,
                },
            )
            return
        if path in ("/v1/replay", "/replay"):
            fixture = str(req.get("fixture") or "")
            helper = req.get("helper")
            helper_s = (
                str(helper) if helper not in (None, "", "null") else None
            )
            try:
                import sys
                from pathlib import Path as _P

                root = _P(__file__).resolve().parents[2]
                py = str(root / "python")
                if py not in sys.path:
                    sys.path.insert(0, py)
                from sparklang.voice_loop.expect_score import (
                    http_replay,
                )

                payload = http_replay(fixture, helper_s)
            except (
                OSError,
                ValueError,
                FileNotFoundError,
                ImportError,
            ) as exc:
                _send(
                    self,
                    400,
                    {
                        "error": "replay_failed",
                        "detail": str(exc),
                    },
                )
                return
            _send(self, 200, payload)
            return
        _send(self, 404, {"error": "not_found", "path": path})


def main() -> None:
    """Serve a helper pack on a local port (shadow or live)."""
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8091)
    ap.add_argument("--helper", required=True)
    ap.add_argument("--as", dest="as_name", default="ranker")
    ap.add_argument(
        "--mode",
        choices=("shadow", "live"),
        default="shadow",
    )
    ap.add_argument(
        "--dry",
        action="store_true",
        help="print plan JSON and exit (no bind)",
    )
    args = ap.parse_args()
    STATE["helper"] = args.helper
    STATE["as_name"] = args.as_name
    STATE["mode"] = args.mode
    plan = {
        "op": "serve_helper",
        "helper": args.helper,
        "as": args.as_name,
        "port": args.port,
        "mode": args.mode,
    }
    if args.dry:
        print(json.dumps(plan, indent=2))
        return
    httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    print(
        f"[spark-serve-ref] {args.as_name} mode={args.mode} "
        f"helper={args.helper} "
        f"http://{args.host}:{args.port}/v1/turn",
        flush=True,
    )
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[spark-serve-ref] stop", flush=True)


if __name__ == "__main__":
    main()
