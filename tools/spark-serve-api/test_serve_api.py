#!/usr/bin/env python3
"""Tests for G-lane spark-serve-api (mock / init weights OK)."""

from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python"))

from sparklang.model_lab.serve_api import ServeEngine  # noqa: E402
from sparklang.model_lab.weights import emit_init_weights  # noqa: E402

SPARKBC = ROOT / "docs/examples/spark-builder.sparkbc"


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


def _write_mock_weights(dest: Path) -> Path:
    """Emit Spark init safetensors (mock weights OK for gate)."""
    assert SPARKBC.is_file(), "missing spark-builder.sparkbc"
    wpath = dest / "weights.safetensors"
    emit_init_weights(
        SPARKBC,
        wpath,
        source=str(SPARKBC),
        command="(test mock)",
    )
    return wpath


def test_stdio_predict_embed() -> None:
    """Stdio JSON predict + embeddings round-trip."""
    with tempfile.TemporaryDirectory() as tmp:
        wpath = _write_mock_weights(Path(tmp))
        eng = ServeEngine(wpath)
        pred = eng.predict({"token_ids": [65, 66, 67]})
        assert pred["op"] == "predict"
        assert pred["production"] is False
        assert isinstance(pred["argmax"], int)
        assert 0 <= pred["argmax"] < pred["vocab"]
        emb = eng.embed({"text": "ABC"})
        assert emb["op"] == "embeddings"
        assert len(emb["embedding"]) == emb["hidden_dim"]
        health = eng.health()
        assert health["ok"] is True
        ver = eng.version()
        assert ver["lane"] == "G"
        assert ver["gpu"] is False


def test_stdio_cli_subprocess() -> None:
    """``python -m … --stdio`` one-shot lines."""
    with tempfile.TemporaryDirectory() as tmp:
        wpath = _write_mock_weights(Path(tmp))
        proc = subprocess.Popen(
            [
                sys.executable,
                "-m",
                "sparklang.model_lab.serve_api",
                "--weights",
                str(wpath),
                "--stdio",
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env={**os.environ, "PYTHONPATH": str(ROOT / "python")},
        )
        assert proc.stdin is not None and proc.stdout is not None
        reqs = (
            json.dumps({"op": "health"})
            + "\n"
            + json.dumps({"op": "predict", "token_ids": [1, 2]})
            + "\n"
            + json.dumps({"op": "embeddings", "token_ids": [3]})
            + "\n"
        )
        out, err = proc.communicate(reqs, timeout=30)
        assert proc.returncode == 0, err
        lines = [ln for ln in out.splitlines() if ln.strip()]
        assert len(lines) == 3
        h = json.loads(lines[0])
        assert h["ok"] is True
        p = json.loads(lines[1])
        assert "argmax" in p
        e = json.loads(lines[2])
        assert "embedding" in e


def test_http_health_predict() -> None:
    """HTTP /health /version /v1/predict with mock weights."""
    with tempfile.TemporaryDirectory() as tmp:
        wpath = _write_mock_weights(Path(tmp))
        port = _free_port()
        eng = ServeEngine(wpath)
        from sparklang.model_lab.serve_api import serve_http

        thr = threading.Thread(
            target=serve_http,
            args=(eng,),
            kwargs={"host": "127.0.0.1", "port": port},
            daemon=True,
        )
        thr.start()
        deadline = time.time() + 5.0
        while time.time() < deadline:
            try:
                with urllib.request.urlopen(
                    f"http://127.0.0.1:{port}/health",
                    timeout=0.5,
                ) as resp:
                    health = json.loads(resp.read().decode())
                    break
            except (urllib.error.URLError, TimeoutError, OSError):
                time.sleep(0.05)
        else:
            raise AssertionError("server did not start")
        assert health["ok"] is True
        with urllib.request.urlopen(
            f"http://127.0.0.1:{port}/version",
            timeout=2,
        ) as resp:
            ver = json.loads(resp.read().decode())
        assert ver["lane"] == "G"
        body = json.dumps({"token_ids": [72, 105]}).encode()
        req = urllib.request.Request(
            f"http://127.0.0.1:{port}/v1/predict",
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            pred = json.loads(resp.read().decode())
        assert "argmax" in pred
        assert pred["production"] is False
        body2 = json.dumps({"text": "Hi"}).encode()
        req2 = urllib.request.Request(
            f"http://127.0.0.1:{port}/v1/embeddings",
            data=body2,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req2, timeout=5) as resp:
            emb = json.loads(resp.read().decode())
        assert len(emb["embedding"]) == emb["hidden_dim"]


def main() -> int:
    """Run gates; exit 1 on failure."""
    test_stdio_predict_embed()
    print("PASS stdio_engine")
    test_stdio_cli_subprocess()
    print("PASS stdio_cli")
    test_http_health_predict()
    print("PASS http_api")
    print("PASS serve-api-g")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
