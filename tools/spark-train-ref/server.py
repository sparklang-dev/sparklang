#!/usr/bin/env python3
"""Reference trainer: Spark multi-method CPU train (not LoRA).

Methods (POST body ``method`` field, default spark_distill_cpu):

  spark_distill_cpu   — reply-class student → weights.pt
  spark_pref_pack     — preference pairs + ranker → pref_pack.json + ranker.pt
  spark_playbook_fit  — intent→playbook router → playbooks.json + router.pt
  spark_faq_index     — FAQ corpus + dual-encoder → faq_index.json + encoder.pt
  spark_reply_pack    — voice+text overlay + behavior lock; never fabricate

HTTP contract:

  POST {SPARK_TRAIN_URL}/jobs
    {"dataset","base","out","backend","method"?}
  GET {SPARK_TRAIN_URL}/jobs/{id}
  POST {SPARK_TRAIN_URL}/replay
    {"fixture","helper"?}  — CPU expect-score replay (Trainer contract)

CPU only. No LoRA / HF PEFT / voice GPU.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Callable
from urllib.parse import urlparse

_REF_DIR = Path(__file__).resolve().parent
if str(_REF_DIR) not in sys.path:
    sys.path.insert(0, str(_REF_DIR))

from common import METHODS  # noqa: E402
from distill_cpu import train_distill  # noqa: E402
from faq_index import train_faq_index  # noqa: E402
from playbook_fit import train_playbook_fit  # noqa: E402
from pref_pack import train_pref_pack  # noqa: E402
from reply_pack import train_reply_pack  # noqa: E402

JOBS: dict[str, dict[str, Any]] = {}
LOCK = threading.Lock()
PREFIX = "/v1"

_TRAINERS: dict[str, Callable[..., dict[str, Any]]] = {
    "spark_distill_cpu": train_distill,
    "spark_pref_pack": train_pref_pack,
    "spark_playbook_fit": train_playbook_fit,
    "spark_faq_index": train_faq_index,
    "spark_reply_pack": train_reply_pack,
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


def _resolve_method(req: dict[str, Any]) -> str:
    method = str(req.get("method") or "").strip()
    if method in _TRAINERS:
        return method
    base = str(req.get("base") or "").strip()
    if base in _TRAINERS:
        return base
    return "spark_distill_cpu"


def _artifact_paths(result: dict[str, Any]) -> dict[str, str]:
    arts = {
        "checkpoint": result["checkpoint"],
        "marker": result["marker"],
        "adapter": result.get("adapter") or result.get("weights", ""),
    }
    for key in (
        "weights",
        "pref_pack",
        "ranker",
        "playbooks",
        "router",
        "faq_index",
        "encoder",
        "replies",
        "gate",
        "router",
    ):
        if key in result and isinstance(result[key], str):
            arts[key] = result[key]
    return arts


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"[spark-train-ref] {self.address_string()} {fmt % args}")

    def do_POST(self) -> None:  # noqa: N802
        path = urlparse(self.path).path.rstrip("/") or "/"
        if path in (f"{PREFIX}/replay", "/replay"):
            req = _json_body(self)
            fixture = str(req.get("fixture") or "")
            helper = req.get("helper")
            helper_s = (
                str(helper) if helper not in (None, "", "null") else None
            )
            try:
                # Local import keeps train-ref usable without voice_loop
                # on PYTHONPATH when only training.
                import sys
                from pathlib import Path as _P

                root = _P(__file__).resolve().parents[2]
                py = str(root / "python")
                if py not in sys.path:
                    sys.path.insert(0, py)
                from sparklang.voice_loop.expect_score import (  # noqa: E402
                    http_replay,
                )

                payload = http_replay(fixture, helper_s)
            except (OSError, ValueError, FileNotFoundError, ImportError) as exc:
                _send(
                    self,
                    400,
                    {
                        "error": "replay_failed",
                        "detail": str(exc),
                        "fixture": fixture,
                        "helper": helper_s,
                    },
                )
                return
            _send(self, 200, payload)
            return
        if path != f"{PREFIX}/jobs":
            _send(self, 404, {"error": "not_found", "path": path})
            return
        req = _json_body(self)
        dataset = str(req.get("dataset") or "")
        base = str(req.get("base") or "")
        out_dir = str(
            req.get("out") or f"out/train/ref-{int(time.time())}"
        )
        backend = str(req.get("backend") or "http")
        method = _resolve_method(req)
        out_name = Path(out_dir).name
        if re.fullmatch(r"job-[A-Za-z0-9._-]+", out_name):
            job_id = out_name
        else:
            job_id = f"job-ref-{uuid.uuid4().hex[:8]}"
        trainer = _TRAINERS[method]
        try:
            if not Path(dataset).is_file():
                raise FileNotFoundError(f"dataset not found: {dataset}")
            result = trainer(dataset, base, out_dir, job_id)
        except (OSError, ValueError, FileNotFoundError) as exc:
            _send(
                self,
                400,
                {
                    "error": "train_failed",
                    "job_id": job_id,
                    "method": method,
                    "detail": str(exc),
                },
            )
            return
        arts = _artifact_paths(result)
        meta = result["meta"]
        note = (
            f"{method} — CPU train "
            f"(loss={meta.get('final_loss')}; not LoRA)"
        )
        rec = {
            "job_id": job_id,
            "status": "accepted",
            "state": "succeeded",
            "dataset": dataset,
            "base": base,
            "out": out_dir,
            "backend": backend,
            "method": method,
            "artifacts": arts,
            "note": note,
            "final_loss": meta.get("final_loss"),
        }
        with LOCK:
            JOBS[job_id] = rec
        _send(
            self,
            200,
            {
                "job_id": job_id,
                "status": "accepted",
                "artifacts": arts,
                "out": out_dir,
                "base": base,
                "dataset": dataset,
                "backend": backend,
                "method": method,
                "note": note,
                "final_loss": meta.get("final_loss"),
                "methods": list(METHODS),
            },
        )

    def do_GET(self) -> None:  # noqa: N802
        path = urlparse(self.path).path.rstrip("/") or "/"
        m = re.fullmatch(rf"{PREFIX}/jobs/([^/]+)", path)
        if not m:
            if path in (PREFIX, f"{PREFIX}/"):
                _send(
                    self,
                    200,
                    {
                        "ok": True,
                        "service": "spark-train-ref",
                        "methods": list(METHODS),
                    },
                )
                return
            _send(self, 404, {"error": "not_found", "path": path})
            return
        job_id = m.group(1)
        with LOCK:
            rec = JOBS.get(job_id)
        if not rec:
            _send(self, 404, {"error": "unknown_job", "job_id": job_id})
            return
        _send(
            self,
            200,
            {
                "job_id": job_id,
                "state": rec["state"],
                "artifacts": rec["artifacts"],
                "out": rec["out"],
                "base": rec["base"],
                "dataset": rec["dataset"],
                "backend": rec["backend"],
                "method": rec["method"],
                "note": rec["note"],
                "final_loss": rec.get("final_loss"),
            },
        )


def main() -> None:
    """Listen for SparkLang multi-method train jobs."""
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8090)
    args = ap.parse_args()
    httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    print(
        "[spark-train-ref] methods="
        + ",".join(METHODS)
        + f" listening http://{args.host}:{args.port}{PREFIX}",
        flush=True,
    )
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[spark-train-ref] stop", flush=True)


if __name__ == "__main__":
    main()
