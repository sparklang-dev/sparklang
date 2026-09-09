#!/usr/bin/env python3
"""Spark eval harness — frozen copy/recall + next-token probes.

Dry fixture (default) or Spark safetensors via --weights /
SPARK_EVAL_WEIGHTS. Optional Claude API baseline when credentials
already exist on the box (--claude auto|on|off). Prints scores;
exits 0 on harness success. Does not claim beat Claude. Never uses
GPU-1 / the 6000. Never invents API keys.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import struct
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from claude_baseline import (  # noqa: E402
    comparison_table,
    run_claude_baseline,
)

SUITE_DEFAULT = ROOT / "examples" / "eval" / "suite.json"
_CLAUDE_MODES = ("off", "auto", "on")


def _load_jsonl(path: Path) -> list[dict[str, Any]]:
    """Load one JSON object per non-empty line."""
    rows: list[dict[str, Any]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        rows.append(json.loads(line))
    return rows


def _bytes_of(text: str) -> list[int]:
    """UTF-8 bytes clamped to Spark stub vocab (0..255)."""
    return list(text.encode("utf-8"))


def _unpack_f32(blob: bytes) -> list[float]:
    n = len(blob) // 4
    return list(struct.unpack("<%df" % n, blob))


def _load_weights(
    path: Path,
) -> tuple[dict[str, str], dict[str, Any]]:
    """Load Spark safetensors via model_lab (no HuggingFace)."""
    from sparklang.model_lab.weights import read_safetensors

    meta, tensors = read_safetensors(path)
    packed: dict[str, Any] = {}
    for name, (shape, blob) in tensors.items():
        packed[name] = {
            "shape": tuple(shape),
            "data": _unpack_f32(blob),
        }
    return meta, packed


def _row(mat: dict[str, Any], i: int) -> list[float]:
    """Row i of a (rows, cols) weight matrix."""
    rows, cols = mat["shape"]
    if i < 0 or i >= rows:
        raise IndexError("row %d out of range %d" % (i, rows))
    base = i * cols
    return mat["data"][base : base + cols]


def _mean_pool(
    embed: dict[str, Any],
    ids: list[int],
) -> list[float]:
    """Mean of embed rows for byte ids (vocab-clamped)."""
    rows, cols = embed["shape"]
    if not ids:
        return [0.0] * cols
    acc = [0.0] * cols
    for b in ids:
        idx = int(b) % rows
        r = _row(embed, idx)
        for j in range(cols):
            acc[j] += r[j]
    n = float(len(ids))
    return [v / n for v in acc]


def _argmax_lm(
    hidden: list[float],
    lm_head: dict[str, Any],
) -> int:
    """Argmax over vocab of lm_head @ hidden (vocab×dim)."""
    vocab, dim = lm_head["shape"]
    if len(hidden) != dim:
        raise ValueError(
            "hidden dim %d != lm_head %d" % (len(hidden), dim)
        )
    best_i = 0
    best_v = -math.inf
    data = lm_head["data"]
    for i in range(vocab):
        base = i * dim
        s = 0.0
        for j in range(dim):
            s += data[base + j] * hidden[j]
        if s > best_v:
            best_v = s
            best_i = i
    return best_i


def _predict_next(
    weights: dict[str, Any],
    context: str,
) -> str:
    """Greedy next UTF-8 byte from mean-pool → lm_head."""
    embed = weights["spark.embed.weight"]
    lm = weights["spark.lm_head.weight"]
    ids = _bytes_of(context)
    hidden = _mean_pool(embed, ids)
    pred = _argmax_lm(hidden, lm)
    try:
        return bytes([pred]).decode("utf-8")
    except UnicodeDecodeError:
        return chr(pred) if pred < 128 else "?"


def score_copy_recall_dry(rows: list[dict[str, Any]]) -> float:
    """Dry oracle: echo want; accuracy is 1.0 if fixtures valid."""
    if not rows:
        return 0.0
    ok = 0
    for row in rows:
        want = str(row.get("want", ""))
        pred = want  # dry oracle
        if want and pred == want:
            ok += 1
    return ok / float(len(rows))


def score_next_token_dry(rows: list[dict[str, Any]]) -> float:
    """Dry oracle: echo want char."""
    if not rows:
        return 0.0
    ok = 0
    for row in rows:
        want = str(row.get("want", ""))
        pred = want
        if want and pred == want:
            ok += 1
    return ok / float(len(rows))


def score_copy_recall_weights(
    rows: list[dict[str, Any]],
    weights: dict[str, Any],
) -> float:
    """Teacher-forced next-byte accuracy over want after prompt."""
    if not rows:
        return 0.0
    total = 0
    correct = 0
    for row in rows:
        prompt = str(row.get("prompt", ""))
        want = str(row.get("want", ""))
        ctx = prompt
        for ch in want:
            pred = _predict_next(weights, ctx)
            total += 1
            if pred == ch:
                correct += 1
            ctx = ctx + ch
    if total == 0:
        return 0.0
    return correct / float(total)


def score_next_token_weights(
    rows: list[dict[str, Any]],
    weights: dict[str, Any],
) -> float:
    """Single next-token accuracy after context."""
    if not rows:
        return 0.0
    ok = 0
    for row in rows:
        ctx = str(row.get("context", ""))
        want = str(row.get("want", ""))
        pred = _predict_next(weights, ctx)
        if want and pred == want:
            ok += 1
    return ok / float(len(rows))


def _normalize_claude_mode(raw: str | None) -> str:
    """Map CLI/env to off|auto|on."""
    if raw is None or not str(raw).strip():
        return "off"
    mode = str(raw).strip().lower()
    if mode in ("0", "false", "no"):
        return "off"
    if mode in ("1", "true", "yes"):
        return "on"
    if mode not in _CLAUDE_MODES:
        raise ValueError(
            "claude mode must be off|auto|on (got %r)" % raw
        )
    return mode


def run_suite(
    suite_path: Path,
    weights_path: Path | None,
    *,
    claude_mode: str = "off",
) -> dict[str, Any]:
    """Run frozen suite; return result dict with scores."""
    claude_mode = _normalize_claude_mode(claude_mode)
    suite = json.loads(suite_path.read_text(encoding="utf-8"))
    mode = "weights" if weights_path else "dry"
    weights: dict[str, Any] | None = None
    meta: dict[str, str] = {}
    if weights_path is not None:
        meta, weights = _load_weights(weights_path)
        for need in (
            "spark.embed.weight",
            "spark.lm_head.weight",
        ):
            if need not in weights:
                raise KeyError("weights missing %s" % need)

    results: list[dict[str, Any]] = []
    probes = list(suite.get("probes", []))
    for probe in probes:
        name = str(probe["name"])
        kind = str(probe["kind"])
        fix = ROOT / str(probe["fixture"])
        if not fix.is_file():
            raise FileNotFoundError(str(fix))
        rows = _load_jsonl(fix)
        if mode == "dry":
            if kind == "copy_recall":
                score = score_copy_recall_dry(rows)
            elif kind == "next_token":
                score = score_next_token_dry(rows)
            else:
                raise ValueError("unknown kind %s" % kind)
            frozen = probe.get("dry_score")
            if frozen is not None and abs(score - 1.0) < 1e-9:
                score = float(frozen)
        else:
            assert weights is not None
            if kind == "copy_recall":
                score = score_copy_recall_weights(rows, weights)
            elif kind == "next_token":
                score = score_next_token_weights(rows, weights)
            else:
                raise ValueError("unknown kind %s" % kind)

        results.append(
            {
                "name": name,
                "kind": kind,
                "metric": probe.get("metric", kind),
                "n": len(rows),
                "score": round(float(score), 6),
                "system": "spark",
            }
        )

    def _rows_for(fixture_rel: str) -> list[dict[str, Any]]:
        return _load_jsonl(ROOT / fixture_rel)

    claude = run_claude_baseline(
        probes,
        _rows_for,
        mode=claude_mode,
    )
    compare = comparison_table(results, claude)

    out: dict[str, Any] = {
        "harness": "spark-eval",
        "suite": str(suite_path.relative_to(ROOT)),
        "mode": mode,
        "claim": "none",
        "beats_claude": False,
        "note": (
            "Scores only — Spark / SparkLang does not claim beat "
            "Claude. Optional Claude baseline is measurement."
        ),
        "probes": results,
        "claude_baseline": claude,
        "comparison": compare,
    }
    if weights_path is not None:
        out["weights"] = str(weights_path)
        out["trained"] = meta.get("trained", "unknown")
        out["sparkbc_sha256"] = meta.get("sparkbc_sha256", "")
    # Suite claim field is informational only; harness never upgrades.
    if suite.get("claim") not in (None, "none"):
        out["suite_claim_ignored"] = suite.get("claim")
    return out


def main() -> int:
    """CLI: dry/weights + optional Claude; print JSON; exit 0/2."""
    ap = argparse.ArgumentParser(
        description=(
            "Spark frozen eval probes (copy/recall, next-token). "
            "Optional Claude baseline if credentials exist. "
            "Exit 0 = harness ran; not a win claim."
        )
    )
    ap.add_argument(
        "--suite",
        type=Path,
        default=SUITE_DEFAULT,
        help="path to suite.json",
    )
    ap.add_argument(
        "--weights",
        type=Path,
        default=None,
        help="Spark safetensors (else dry fixture)",
    )
    ap.add_argument(
        "--claude",
        default=None,
        help="Claude baseline: off|auto|on (default off; "
        "env SPARK_EVAL_CLAUDE)",
    )
    args = ap.parse_args()
    weights = args.weights
    env_w = os.environ.get("SPARK_EVAL_WEIGHTS", "").strip()
    if weights is None and env_w:
        weights = Path(env_w)
    if weights is not None and not weights.is_file():
        print(
            "spark-eval: weights not found: %s" % weights,
            file=sys.stderr,
        )
        return 2

    claude_raw = args.claude
    if claude_raw is None:
        claude_raw = os.environ.get("SPARK_EVAL_CLAUDE", "off")
    try:
        claude_mode = _normalize_claude_mode(claude_raw)
    except ValueError as exc:
        print("spark-eval: %s" % exc, file=sys.stderr)
        return 2

    try:
        result = run_suite(
            args.suite, weights, claude_mode=claude_mode
        )
    except (
        OSError,
        KeyError,
        ValueError,
        json.JSONDecodeError,
    ) as exc:
        print("spark-eval: %s" % exc, file=sys.stderr)
        return 2

    claude = result.get("claude_baseline") or {}
    if claude_mode == "on" and claude.get("status") not in (
        "ran",
    ):
        err = claude.get("error") or claude.get("status")
        print(
            "spark-eval: Claude baseline required but %s" % err,
            file=sys.stderr,
        )
        print(json.dumps(result, indent=2, sort_keys=False))
        return 2

    print(json.dumps(result, indent=2, sort_keys=False))
    print("---")
    for p in result["probes"]:
        print(
            "spark %-16s %.4f  (n=%d, %s)"
            % (p["name"], p["score"], p["n"], p["metric"])
        )
    cstat = claude.get("status", "off")
    print("claude_baseline status=%s" % cstat)
    if cstat == "ran":
        for p in claude.get("probes") or []:
            print(
                "claude %-15s %.4f  (n=%d, %s)"
                % (p["name"], p["score"], p["n"], p["metric"])
            )
        for row in (result.get("comparison") or {}).get(
            "rows"
        ) or []:
            print(
                "compare %-14s spark=%s claude=%s"
                % (
                    row["name"],
                    row.get("spark_score"),
                    row.get("claude_score"),
                )
            )
    print(
        "mode=%s claim=%s beats_claude=%s — not beat Claude"
        % (
            result["mode"],
            result["claim"],
            result.get("beats_claude"),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
