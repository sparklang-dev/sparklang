#!/usr/bin/env python3
"""Deepgram batch transcription CLI for wav manifests.

Reads a jsonl manifest of rows that each carry a ``wav`` path, sends
each clip to the Deepgram REST API (default model ``nova-3``), and
writes the manifest back out with ``dg_transcript``, ``dg_confidence``,
and ``dg_model`` filled in. Results are cached (content-hash keyed) so
re-runs do not re-bill unchanged audio.

Credential handling: the key comes from ``DEEPGRAM_API_KEY`` (or the
``~/.config/voicecore/.env`` fallback loader in dg_common) and is only
ever held in memory. ``--dry`` validates inputs and reports the plan
without any network access.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from dg_common import (  # noqa: E402
    DEFAULT_MODEL,
    CredentialUnavailable,
    load_deepgram_key,
    read_jsonl,
    transcribe_wav,
    write_jsonl,
)
from el_inventory import sha256_file  # noqa: E402

DEFAULT_CACHE = "dg_cache.json"


def resolve_wav(row: dict, manifest_path: Path) -> Path:
    """Resolve a row's wav path relative to the manifest's directory."""
    wav = Path(row["wav"])
    if wav.is_absolute():
        return wav
    candidate = manifest_path.parent / wav
    if candidate.is_file():
        return candidate
    return wav


def load_cache(cache_path: Path) -> dict:
    """Load the transcript cache ({} when absent or corrupt)."""
    try:
        return json.loads(cache_path.read_text())
    except (OSError, json.JSONDecodeError):
        return {}


def transcribe_manifest(
    rows: list[dict],
    manifest_path: Path,
    api_key: str,
    model: str,
    cache: dict,
    sleep_s: float,
    limit: int | None,
) -> tuple[list[dict], int, int]:
    """Transcribe rows in place; return (rows, n_new, n_cached)."""
    n_new = 0
    n_cached = 0
    for index, row in enumerate(rows):
        if limit is not None and index >= limit:
            break
        wav_path = resolve_wav(row, manifest_path)
        if not wav_path.is_file():
            row["dg_error"] = f"missing wav: {wav_path}"
            continue
        clip_hash = row.get("sha256") or sha256_file(wav_path)
        cache_key = f"{model}:{clip_hash}"
        if cache_key in cache:
            entry = cache[cache_key]
            n_cached += 1
        else:
            try:
                entry = transcribe_wav(wav_path, api_key, model=model)
            except urllib.error.HTTPError as exc:
                row["dg_error"] = f"http {exc.code}"
                continue
            except (urllib.error.URLError, TimeoutError) as exc:
                row["dg_error"] = f"transport: {exc.__class__.__name__}"
                continue
            cache[cache_key] = entry
            n_new += 1
            if sleep_s > 0:
                time.sleep(sleep_s)
        row["dg_transcript"] = entry.get("transcript", "")
        row["dg_confidence"] = entry.get("confidence")
        row["dg_model"] = entry.get("model", model)
        row.pop("dg_error", None)
    return rows, n_new, n_cached


def main() -> int:
    """Batch-transcribe a wav manifest via Deepgram."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument(
        "--out",
        type=Path,
        default=None,
        help="output jsonl (default: overwrite --manifest in place)",
    )
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument(
        "--cache",
        type=Path,
        default=None,
        help=f"cache json (default: <manifest dir>/{DEFAULT_CACHE})",
    )
    parser.add_argument("--sleep", type=float, default=0.2)
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument(
        "--dry",
        action="store_true",
        help="validate and report the plan; no network, no writes",
    )
    args = parser.parse_args()

    rows = read_jsonl(args.manifest)
    with_wav = [r for r in rows if r.get("wav")]
    planned = with_wav if args.limit is None else with_wav[: args.limit]
    print(f"manifest rows: {len(rows)}; with wav: {len(with_wav)}")
    print(f"would transcribe: {len(planned)} clip(s) with {args.model}")

    if args.dry:
        missing = [
            str(resolve_wav(r, args.manifest))
            for r in planned
            if not resolve_wav(r, args.manifest).is_file()
        ]
        print(f"missing wavs: {len(missing)}")
        for path in missing[:10]:
            print(f"  MISSING {path}")
        print("dry run: no network calls made, nothing written")
        return 0 if not missing else 1

    try:
        api_key = load_deepgram_key()
    except CredentialUnavailable as exc:
        print(str(exc), file=sys.stderr)
        return 3

    cache_path = args.cache or (args.manifest.parent / DEFAULT_CACHE)
    cache = load_cache(cache_path)
    rows, n_new, n_cached = transcribe_manifest(
        rows, args.manifest, api_key, args.model, cache, args.sleep,
        args.limit,
    )
    cache_path.write_text(json.dumps(cache, indent=1) + "\n")
    out_path = args.out or args.manifest
    write_jsonl(out_path, rows)
    errors = [r for r in planned if r.get("dg_error")]
    print(f"transcribed: {n_new} new, {n_cached} cached, "
          f"{len(errors)} error(s)")
    print(f"wrote {out_path} and cache {cache_path}")
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
