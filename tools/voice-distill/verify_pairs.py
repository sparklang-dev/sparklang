#!/usr/bin/env python3
"""Verify EL audio+text pairs by independent Deepgram transcription.

Each clip in ``el_manifest.jsonl`` is transcribed with Deepgram (via
dg_transcribe's cached batch path) and the transcript is scored against
the known script text with stdlib WER/CER (case/punct normalized). A
pair passes when ``wer <= 0.1``. Output:

- ``el_verified.jsonl`` — manifest rows plus wer/cer/pass fields
- ``verify_stats.json`` — pass rate and WER distribution

This flags bad EL generations so training only consumes clean pairs.
When no Deepgram credential is available the tool exits 3 after the
``--dry``-style plan; the pipeline plugs in later with no code changes.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from dg_common import (  # noqa: E402
    DEFAULT_MODEL,
    CredentialUnavailable,
    best_error_rates,
    load_deepgram_key,
    read_jsonl,
    write_jsonl,
)
from dg_transcribe import load_cache, transcribe_manifest  # noqa: E402
from el_inventory import DEFAULT_OUT_DIR  # noqa: E402

PASS_WER = 0.1
WER_BUCKETS = ("0.00", "(0,0.05]", "(0.05,0.1]", "(0.1,0.25]", ">0.25")


def wer_bucket(wer: float) -> str:
    """Histogram bucket label for a WER value."""
    if wer == 0.0:
        return "0.00"
    if wer <= 0.05:
        return "(0,0.05]"
    if wer <= 0.1:
        return "(0.05,0.1]"
    if wer <= 0.25:
        return "(0.1,0.25]"
    return ">0.25"


def score_rows(rows: list[dict]) -> list[dict]:
    """Attach strict + spoken-form wer/cer and pass to each row."""
    for row in rows:
        transcript = row.get("dg_transcript")
        if transcript is None:
            row["pass"] = False
            row["score_error"] = row.get("dg_error", "no transcript")
            continue
        row.update(best_error_rates(row["text"], transcript))
        row["pass"] = row["wer"] <= PASS_WER
    return rows


def build_stats(rows: list[dict], model: str) -> dict:
    """Aggregate pass rate and WER distribution."""
    scored = [r for r in rows if "wer" in r]
    wers = [r["wer"] for r in scored]
    passed = sum(1 for r in scored if r["pass"])
    passed_strict = sum(
        1 for r in scored if r["wer_strict"] <= PASS_WER
    )
    histogram = {bucket: 0 for bucket in WER_BUCKETS}
    for wer in wers:
        histogram[wer_bucket(wer)] += 1
    return {
        "model": model,
        "pass_wer_threshold": PASS_WER,
        "total_pairs": len(rows),
        "scored_pairs": len(scored),
        "passed": passed,
        "pass_rate": round(passed / len(scored), 4) if scored else None,
        "passed_strict_normalization": passed_strict,
        "pass_rate_strict": (
            round(passed_strict / len(scored), 4) if scored else None
        ),
        "wer_mean": round(statistics.fmean(wers), 4) if wers else None,
        "wer_median": round(statistics.median(wers), 4) if wers else None,
        "wer_max": max(wers) if wers else None,
        "wer_histogram": histogram,
        "unscored_ids": [r["id"] for r in rows if "wer" not in r],
    }


def main() -> int:
    """Transcribe + score EL pairs; write verified manifest and stats."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--manifest",
        type=Path,
        default=DEFAULT_OUT_DIR / "el_manifest.jsonl",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=DEFAULT_OUT_DIR / "el_verified.jsonl",
    )
    parser.add_argument(
        "--stats",
        type=Path,
        default=DEFAULT_OUT_DIR / "verify_stats.json",
    )
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--sleep", type=float, default=0.2)
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument(
        "--dry",
        action="store_true",
        help="plan only; no network, no writes",
    )
    args = parser.parse_args()

    rows = read_jsonl(args.manifest)
    planned = rows if args.limit is None else rows[: args.limit]
    print(f"pairs to verify: {len(planned)} (model {args.model})")

    if args.dry:
        print("dry run: no network calls made, nothing written")
        return 0

    try:
        api_key = load_deepgram_key()
    except CredentialUnavailable as exc:
        print(str(exc), file=sys.stderr)
        print(
            "verification is wired for Deepgram; re-run once "
            "DEEPGRAM_API_KEY is present",
            file=sys.stderr,
        )
        return 3

    cache_path = args.manifest.parent / "dg_cache.json"
    cache = load_cache(cache_path)
    rows, n_new, n_cached = transcribe_manifest(
        rows, args.manifest, api_key, args.model, cache, args.sleep,
        args.limit,
    )
    cache_path.write_text(json.dumps(cache, indent=1) + "\n")

    rows = score_rows(rows)
    write_jsonl(args.out, rows)
    stats = build_stats(rows, args.model)
    args.stats.write_text(json.dumps(stats, indent=2) + "\n")

    print(f"transcribed: {n_new} new, {n_cached} cached")
    print(
        f"pass rate: {stats['passed']}/{stats['scored_pairs']} "
        f"({stats['pass_rate']})"
    )
    print(f"wer mean={stats['wer_mean']} median={stats['wer_median']} "
          f"max={stats['wer_max']}")
    print(f"wrote {args.out} and {args.stats}")
    return 0 if stats["scored_pairs"] == stats["total_pairs"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
