#!/usr/bin/env python3
"""JSON-path numeric / histogram / score expects for SparkLang.

Forms (full statement in --stmt-file; bound JSON in --got-file):

  expect gte NAME $.path 0.8
  expect lte NAME $.path 1.0
  expect eq NAME $.path true
  expect histogram_min NAME CLASS N
  expect score NAME $.path using \"URL\" >= N

Dry-run score uses fixture examples/fixtures/eval/want_score.txt
(or SPARK_EXPECT_SCORE_FIXTURE). Live score POSTs to an OpenAI-
compatible chat endpoint with a rubric (SPARK_EXPECT_RUBRIC).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


def _die(msg: str, code: int = 1) -> None:
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(code)


def _json_path(obj: Any, path: str) -> Any:
    if not path.startswith("$"):
        _die(f"jsonpath must start with $, got {path!r}")
    cur: Any = obj
    if path == "$":
        return cur
    if not path.startswith("$."):
        _die(f"bad jsonpath {path!r}")
    for part in path[2:].split("."):
        if part == "":
            _die(f"bad jsonpath {path!r}")
        key = part
        idx = None
        m = re.fullmatch(r"([^\[\]]+)\[(\d+)\]", part)
        if m:
            key, idx = m.group(1), int(m.group(2))
        if not isinstance(cur, dict) or key not in cur:
            _die(f"jsonpath miss {path!r} at {key!r}")
        cur = cur[key]
        if idx is not None:
            if not isinstance(cur, list) or idx >= len(cur):
                _die(f"jsonpath index miss {path!r}")
            cur = cur[idx]
    return cur


def _parse_stmt(stmt: str) -> dict[str, Any]:
    s = stmt.strip()
    if s.startswith("expect"):
        s = s[6:].strip()
    # score form first
    m = re.match(
        r"(score)\s+(\S+)\s+(\$\S+)\s+using\s+\"([^\"]+)\"\s*"
        r"(?:>=\s*)?([0-9.]+)\s*$",
        s,
    )
    if m:
        return {
            "mode": "score",
            "name": m.group(2),
            "path": m.group(3),
            "endpoint": m.group(4),
            "want": float(m.group(5)),
        }
    m = re.match(
        r"(histogram_min)\s+(\S+)\s+(\S+)\s+(\d+)\s*$",
        s,
    )
    if m:
        return {
            "mode": "histogram_min",
            "name": m.group(2),
            "klass": m.group(3),
            "want": int(m.group(4)),
        }
    m = re.match(
        r"(gte|lte|eq)\s+(\S+)\s+(\$\S+)\s*(?:>=\s*|<=\s*|==\s*)?"
        r"(\S+)\s*$",
        s,
    )
    if m:
        return {
            "mode": m.group(1),
            "name": m.group(2),
            "path": m.group(3),
            "want": m.group(4),
        }
    _die(f"cannot parse expect stmt: {stmt!r}")


def _as_bool(v: Any) -> bool:
    if isinstance(v, bool):
        return v
    if isinstance(v, str):
        return v.lower() in ("true", "1", "yes")
    return bool(v)


def _coerce_want(mode: str, raw: str) -> Any:
    if mode == "eq":
        low = raw.lower()
        if low == "true":
            return True
        if low == "false":
            return False
        try:
            if "." in raw:
                return float(raw)
            return int(raw)
        except ValueError:
            return raw.strip('"')
    return float(raw)


def _check(
    mode: str,
    got_obj: Any,
    spec: dict[str, Any],
    *,
    dry: bool,
) -> None:
    if mode == "histogram_min":
        hist = got_obj.get("class_histogram") or got_obj.get(
            "metrics", {}
        ).get("class_histogram")
        if not isinstance(hist, dict):
            # also allow top-level metrics nested
            hist = (got_obj.get("metrics") or {}).get("class_histogram")
        if not isinstance(hist, dict):
            hist = {}
        klass = spec["klass"]
        n = int(hist.get(klass, 0))
        want = int(spec["want"])
        if n < want:
            _die(
                f"expect histogram_min {klass}: got {n} want >={want}"
            )
        print(f"[expect] pass histogram_min {klass} {n}>={want}")
        return

    if mode == "score":
        path = spec["path"]
        samples = _json_path(got_obj, path)
        want = float(spec["want"])
        if dry:
            fx = os.environ.get(
                "SPARK_EXPECT_SCORE_FIXTURE",
                "examples/fixtures/eval/want_score.txt",
            )
            p = Path(fx)
            if not p.is_file():
                _die(f"score fixture missing: {fx}")
            score = float(p.read_text(encoding="utf-8").strip())
        else:
            score = _live_score(
                samples, spec["endpoint"], want_floor=want
            )
        if score < want:
            _die(f"expect score {path}: got {score} want >={want}")
        print(f"[expect] pass score {path} {score}>={want}")
        return

    path = spec["path"]
    val = _json_path(got_obj, path)
    want = _coerce_want(mode, str(spec["want"]))
    if mode == "gte":
        if float(val) < float(want):
            _die(f"expect gte {path}: got {val} want >={want}")
    elif mode == "lte":
        if float(val) > float(want):
            _die(f"expect lte {path}: got {val} want <={want}")
    elif mode == "eq":
        if isinstance(want, bool):
            ok = _as_bool(val) == want
        else:
            ok = val == want or str(val) == str(want)
        if not ok:
            _die(f"expect eq {path}: got {val!r} want {want!r}")
    else:
        _die(f"unknown mode {mode}")
    print(f"[expect] pass {mode} {path}")


def _live_score(samples: Any, endpoint: str, *, want_floor: float) -> float:
    rubric = os.environ.get(
        "SPARK_EXPECT_RUBRIC",
        "Score 0-10 how well the samples meet the task. "
        "Reply with JSON {\"score\": N} only.",
    )
    body = {
        "model": os.environ.get("SPARK_EXPECT_MODEL", "gpt-4o-mini"),
        "messages": [
            {"role": "system", "content": rubric},
            {
                "role": "user",
                "content": json.dumps(samples, ensure_ascii=False)[:8000],
            },
        ],
        "temperature": 0,
        "max_tokens": 64,
    }
    url = endpoint.rstrip("/")
    if not url.endswith("/chat/completions"):
        url = url + "/chat/completions"
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": (
                "Bearer "
                + (os.environ.get("SPARK_EXPECT_TOKEN") or os.environ.get("OPENAI_API_KEY") or "")
            ),
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        _die(f"score endpoint failed: {exc}")
    text = payload["choices"][0]["message"]["content"]
    m = re.search(r"\{[^}]*\"score\"\s*:\s*([0-9.]+)", text)
    if not m:
        m2 = re.search(r"([0-9]+(?:\.[0-9]+)?)", text)
        if not m2:
            _die(f"score parse failed: {text!r}")
        return float(m2.group(1))
    return float(m.group(1))


def main(argv: list[str] | None = None) -> int:
    """CLI entry for JSON expects."""
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry", action="store_true", default=True)
    ap.add_argument("--live", action="store_true")
    ap.add_argument("--stmt-file")
    ap.add_argument("--got-file", required=True)
    ap.add_argument("--out")
    args = ap.parse_args(argv)
    dry = not args.live
    got_raw = Path(args.got_file).read_text(encoding="utf-8")
    try:
        got_obj = json.loads(got_raw)
    except json.JSONDecodeError:
        _die("got-file is not JSON (numeric expects need bound JSON)")
    if not args.stmt_file:
        _die("--stmt-file required")
    stmt = Path(args.stmt_file).read_text(encoding="utf-8")
    spec = _parse_stmt(stmt)
    _check(spec["mode"], got_obj, spec, dry=dry)
    if args.out:
        Path(args.out).write_text("pass\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
