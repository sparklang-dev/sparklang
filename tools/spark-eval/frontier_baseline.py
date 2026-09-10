#!/usr/bin/env python3
"""Optional frontier-API baseline for spark-eval (honest measurement).

Calls the Anthropic Messages API only when a real key is already on
the box. Never invents credentials. Never upgrades ``claim`` to a
win — side-by-side scores are measurement only. CPU / HTTPS only —
never GPU-1 / the 6000.
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Callable

# Env names checked in order. Values are never logged.
_KEY_ENVS = (
    "SPARK_EVAL_FRONTIER_API_KEY",
    "ANTHROPIC_API_KEY",
)

# Anthropic model id for the cheap baseline tier (API identifier).
_DEFAULT_MODEL = "claude-3-5-haiku-latest"
_API_URL = "https://api.anthropic.com/v1/messages"
_ANTHROPIC_VERSION = "2023-06-01"


def discover_frontier_api_key() -> tuple[str | None, str]:
    """Return (key_or_none, status). status is machine-readable."""
    for name in _KEY_ENVS:
        raw = os.environ.get(name, "").strip()
        if raw:
            return raw, "credentials_env:%s" % name
    key_file = os.environ.get("SPARK_EVAL_FRONTIER_KEY_FILE", "").strip()
    if key_file:
        path = Path(key_file)
        if path.is_file():
            text = path.read_text(encoding="utf-8").strip()
            if text:
                return text, "credentials_file"
            return None, "skipped_empty_key_file"
        return None, "skipped_missing_key_file"
    return None, "skipped_no_credentials"


def frontier_model() -> str:
    """Model id from env or the default cheap baseline tier."""
    return (
        os.environ.get("SPARK_EVAL_FRONTIER_MODEL", "").strip()
        or _DEFAULT_MODEL
    )


def _post_messages(
    api_key: str,
    user_text: str,
    *,
    max_tokens: int = 32,
    opener: Callable[..., Any] | None = None,
) -> str:
    """One Messages API completion; returns assistant text."""
    body = {
        "model": frontier_model(),
        "max_tokens": max_tokens,
        "messages": [
            {"role": "user", "content": user_text},
        ],
    }
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        _API_URL,
        data=data,
        method="POST",
        headers={
            "content-type": "application/json",
            "x-api-key": api_key,
            "anthropic-version": _ANTHROPIC_VERSION,
        },
    )
    open_fn = opener or urllib.request.urlopen
    with open_fn(req, timeout=60) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    parts: list[str] = []
    for block in payload.get("content") or []:
        if isinstance(block, dict) and block.get("type") == "text":
            parts.append(str(block.get("text") or ""))
    return "".join(parts).strip()


def _first_line(text: str) -> str:
    """First non-empty line, stripped."""
    for line in text.splitlines():
        line = line.strip()
        if line:
            return line
    return text.strip()


def predict_copy_recall(
    api_key: str,
    prompt: str,
    *,
    opener: Callable[..., Any] | None = None,
) -> str:
    """Ask the frontier model to answer the copy/recall probe."""
    user = (
        "You are a exact-string baseline. Reply with ONLY the "
        "requested string — no quotes, no explanation.\n\n"
        "%s" % prompt
    )
    return _first_line(
        _post_messages(api_key, user, max_tokens=32, opener=opener)
    )


def predict_next_token(
    api_key: str,
    context: str,
    *,
    opener: Callable[..., Any] | None = None,
) -> str:
    """Ask the frontier model for the single next UTF-8 character."""
    user = (
        "Complete the next single character after this context. "
        "Reply with ONLY that one character.\n\n"
        "context: %s" % context
    )
    text = _post_messages(
        api_key, user, max_tokens=8, opener=opener
    )
    if not text:
        return ""
    return text[0]


def score_copy_recall_frontier(
    rows: list[dict[str, Any]],
    api_key: str,
    *,
    opener: Callable[..., Any] | None = None,
) -> float:
    """Exact-match accuracy for copy_recall rows via frontier API."""
    if not rows:
        return 0.0
    ok = 0
    for row in rows:
        prompt = str(row.get("prompt", ""))
        want = str(row.get("want", ""))
        pred = predict_copy_recall(
            api_key, prompt, opener=opener
        )
        if want and pred == want:
            ok += 1
    return ok / float(len(rows))


def score_next_token_frontier(
    rows: list[dict[str, Any]],
    api_key: str,
    *,
    opener: Callable[..., Any] | None = None,
) -> float:
    """Next-char accuracy for next_token rows via frontier API."""
    if not rows:
        return 0.0
    ok = 0
    for row in rows:
        ctx = str(row.get("context", ""))
        want = str(row.get("want", ""))
        pred = predict_next_token(api_key, ctx, opener=opener)
        if want and pred == want:
            ok += 1
    return ok / float(len(rows))


def run_frontier_baseline(
    probes: list[dict[str, Any]],
    load_rows: Callable[[str], list[dict[str, Any]]],
    *,
    mode: str,
    opener: Callable[..., Any] | None = None,
) -> dict[str, Any]:
    """Run or skip the frontier-API baseline. Never a win claim.

    mode: off | auto | on
    """
    base: dict[str, Any] = {
        "requested": mode,
        "status": "off",
        "model": frontier_model(),
        "probes": [],
        "claim": "none",
        "note": (
            "Optional frontier-API baseline only. Side-by-side "
            "scores are measurement — Spark / SparkLang never "
            "claims a frontier win from this harness."
        ),
    }
    if mode == "off":
        base["status"] = "off"
        return base

    key, status = discover_frontier_api_key()
    if key is None:
        base["status"] = status
        if mode == "on":
            base["error"] = (
                "FRONTIER=on but no credentials on box "
                "(checked SPARK_EVAL_FRONTIER_API_KEY, "
                "ANTHROPIC_API_KEY, "
                "SPARK_EVAL_FRONTIER_KEY_FILE)"
            )
        return base

    results: list[dict[str, Any]] = []
    try:
        for probe in probes:
            name = str(probe["name"])
            kind = str(probe["kind"])
            fixture = str(probe["fixture"])
            rows = load_rows(fixture)
            if kind == "copy_recall":
                score = score_copy_recall_frontier(
                    rows, key, opener=opener
                )
            elif kind == "next_token":
                score = score_next_token_frontier(
                    rows, key, opener=opener
                )
            else:
                raise ValueError("unknown kind %s" % kind)
            results.append(
                {
                    "name": name,
                    "kind": kind,
                    "metric": probe.get("metric", kind),
                    "n": len(rows),
                    "score": round(float(score), 6),
                    "system": "frontier",
                }
            )
    except (
        urllib.error.URLError,
        urllib.error.HTTPError,
        OSError,
        TimeoutError,
        json.JSONDecodeError,
        KeyError,
        ValueError,
    ) as exc:
        base["status"] = "error"
        base["error"] = "%s: %s" % (type(exc).__name__, exc)
        base["probes"] = results
        # Still never a win claim.
        base["claim"] = "none"
        return base

    base["status"] = "ran"
    base["credential_source"] = status
    base["probes"] = results
    base["claim"] = "none"
    return base


def comparison_table(
    spark_probes: list[dict[str, Any]],
    frontier_block: dict[str, Any],
) -> dict[str, Any]:
    """Side-by-side Spark vs frontier scores; never a win claim."""
    by_name = {
        str(p["name"]): p for p in (frontier_block.get("probes") or [])
    }
    rows: list[dict[str, Any]] = []
    for sp in spark_probes:
        name = str(sp["name"])
        cp = by_name.get(name)
        row: dict[str, Any] = {
            "name": name,
            "spark_score": sp.get("score"),
            "frontier_score": None if cp is None else cp.get("score"),
        }
        rows.append(row)
    return {
        "rows": rows,
        "claim": "none",
        "note": (
            "Head-to-head measurement table only. "
            "Higher Spark score is not a frontier win claim."
        ),
    }
