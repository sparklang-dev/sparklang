#!/usr/bin/env python3
"""Minimal reference trainer for SparkLang's HTTP train contract.

Implements only what spark-train-http actually calls:

  POST {SPARK_TRAIN_URL}/jobs
    body: {"dataset","base","out","backend"}
    → {"job_id","status","artifacts"}

  GET {SPARK_TRAIN_URL}/jobs/{id}
    → {"job_id","state","artifacts"}

Writes a real adapter file under the requested out dir (not a dry-run
fixture path). No GPU. No invented weights - bytes are a marker.

  python3 tools/spark-train-ref/server.py --host 127.0.0.1 --port 8090
  export SPARK_TRAIN_URL=http://127.0.0.1:8090/v1
  ./spark-train-http --live --submit ...
"""
from __future__ import annotations

import argparse
import json
import os
import re
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

JOBS: dict[str, dict[str, Any]] = {}
LOCK = threading.Lock()
PREFIX = "/v1"


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


def _artifacts(out_dir: str) -> dict[str, str]:
    return {
        "adapter": f"{out_dir}/adapter.bin",
        "checkpoint": f"{out_dir}/checkpoint.json",
        "marker": f"{out_dir}/ARTIFACT",
    }


def _write_artifacts(out_dir: str, job_id: str, base: str, dataset: str) -> dict[str, str]:
    root = Path(out_dir)
    root.mkdir(parents=True, exist_ok=True)
    arts = _artifacts(out_dir)
    adapter = Path(arts["adapter"])
    # Real file created by the server - not a dry-run stub path in copy.
    adapter.write_bytes(
        b"spark-train-ref adapter marker\n"
        + f"job_id={job_id}\nbase={base}\ndataset={dataset}\n".encode()
    )
    Path(arts["checkpoint"]).write_text(
        json.dumps(
            {
                "job_id": job_id,
                "base": base,
                "dataset": dataset,
                "note": "reference trainer - no real weights",
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    Path(arts["marker"]).write_text(
        f"spark-train-ref {job_id}\nadapter={arts['adapter']}\n",
        encoding="utf-8",
    )
    return arts


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"[spark-train-ref] {self.address_string()} {fmt % args}")

    def do_POST(self) -> None:  # noqa: N802
        path = urlparse(self.path).path.rstrip("/") or "/"
        if path != f"{PREFIX}/jobs":
            _send(self, 404, {"error": "not_found", "path": path})
            return
        req = _json_body(self)
        dataset = str(req.get("dataset") or "")
        base = str(req.get("base") or "")
        out_dir = str(req.get("out") or f"out/train/ref-{int(time.time())}")
        backend = str(req.get("backend") or "http")
        job_id = f"job-ref-{uuid.uuid4().hex[:8]}"
        arts = _write_artifacts(out_dir, job_id, base, dataset)
        rec = {
            "job_id": job_id,
            "status": "accepted",
            "state": "succeeded",
            "dataset": dataset,
            "base": base,
            "out": out_dir,
            "backend": backend,
            "artifacts": arts,
            "note": "spark-train-ref - filesystem marker only, no GPU",
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
                "note": rec["note"],
            },
        )

    def do_GET(self) -> None:  # noqa: N802
        path = urlparse(self.path).path.rstrip("/") or "/"
        m = re.fullmatch(rf"{PREFIX}/jobs/([^/]+)", path)
        if not m:
            if path in (PREFIX, f"{PREFIX}/"):
                _send(self, 200, {"ok": True, "service": "spark-train-ref"})
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
                "note": rec["note"],
            },
        )


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8090)
    args = ap.parse_args()
    httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    print(
        f"[spark-train-ref] listening http://{args.host}:{args.port}{PREFIX}"
        f"  (SPARK_TRAIN_URL=http://{args.host}:{args.port}{PREFIX})",
        flush=True,
    )
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[spark-train-ref] stop", flush=True)


if __name__ == "__main__":
    main()
