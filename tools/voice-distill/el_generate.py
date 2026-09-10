#!/usr/bin/env python3
"""Generate the EL (Rachel) training corpus from LJSpeech texts.

Batch-1 of the voice-distill corpus lane: synthesize up to
``--max-utterances`` (default 2000) LJSpeech sentences with the existing
ElevenLabs Rachel voice (``eleven_flash_v2_5`` — the same model/voice
the bench ``reference-el`` clips used, per render_references.py), write
22050 Hz mono wavs to ``data/voice/distill/el_audio/``, and append
inventory-compatible rows to ``el_manifest.jsonl``.

Discipline:

- hash-dedupe + resume: ids / text sha256 already generated are never
  regenerated; interrupted runs continue where they stopped. The
  append-only ``el_generated.jsonl`` journal is this lane's source of
  truth; manifest rows are re-appended from it when missing (e.g.
  after an ``el_inventory.py`` rebuild).
- polite rate limit: at most 2 concurrent requests, per-request sleep,
  exponential backoff on 429/5xx honoring ``Retry-After``.
- spend bound: stop after ``--max-utterances`` / ``--max-chars``, and
  halt early when the ElevenLabs subscription quota drops below
  ``--quota-floor-chars``. A spend checkpoint (local characters billed
  plus the API's character_count / character_limit) is recorded at
  start, at every checkpoint, and at stop in ``el_spend_checkpoint.json``.
- verify-as-you-go: every ``--checkpoint-every`` utterances the merged
  Deepgram verifier (``verify_pairs.py``) re-runs on the manifest
  (cache-incremental); current failures (wer > 0.1 under both strict
  and spoken normalizations) are rebuilt into ``el_quarantine.jsonl``
  with reasons.

Audio is requested as ``pcm_22050`` (lossless 22050 Hz mono s16) and
wrapped in a wav header directly — no mp3 transcode step.

Credentials: ``ELEVENLABS_API_KEY`` / ``ELEVENLABS_TTS_VOICE_ID`` from
the process environment or ``~/.config/voicecore/.env`` (same loader
policy as dg_common). Keys live in memory only — never printed, logged,
written to disk, or committed. Exit 3 = credential unavailable,
exit 4 = another run holds the lock.
"""

from __future__ import annotations

import argparse
import datetime
import fcntl
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
import wave
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from dg_common import read_jsonl, write_jsonl  # noqa: E402
from el_inventory import (  # noqa: E402
    DEFAULT_OUT_DIR,
    VOICE_LABEL,
    sha256_file,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_METADATA = (
    REPO_ROOT / "data" / "voice" / "LJSpeech-1.1" / "metadata.csv"
)
DEFAULT_ENV_FILES = (Path.home() / ".config" / "voicecore" / ".env",)

TTS_URL = "https://api.elevenlabs.io/v1/text-to-speech"
SUBSCRIPTION_URL = "https://api.elevenlabs.io/v1/user/subscription"
DEFAULT_MODEL = "eleven_flash_v2_5"
OUTPUT_FORMAT = "pcm_22050"
SAMPLE_RATE = 22050
MAX_CONCURRENCY = 2
BUCKET = "ljspeech"

JOURNAL_NAME = "el_generated.jsonl"
MANIFEST_NAME = "el_manifest.jsonl"
QUARANTINE_NAME = "el_quarantine.jsonl"
ERRORS_NAME = "el_generate_errors.jsonl"
SPEND_NAME = "el_spend_checkpoint.json"
GEN_STATS_NAME = "el_generate_stats.json"
VERIFIED_NAME = "el_verified.jsonl"
VERIFY_STATS_NAME = "verify_stats.json"
LOCK_NAME = ".el_generate.lock"


class CredentialUnavailable(RuntimeError):
    """Raised when no ElevenLabs credential can be located."""


class GenerationFailed(RuntimeError):
    """Raised when one utterance fails permanently or exhausts retries."""


def utc_now() -> str:
    """ISO-8601 UTC timestamp."""
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def text_sha256(text: str) -> str:
    """Content hash of one source text (dedupe key)."""
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def load_env_value(
    name: str, env_files: tuple[Path, ...] = DEFAULT_ENV_FILES
) -> str:
    """Return env var ``name`` (or first key=value file hit) or ''."""
    value = os.environ.get(name, "").strip()
    if value:
        return value
    for path in env_files:
        try:
            lines = path.read_text().splitlines()
        except OSError:
            continue
        for line in lines:
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            if "=" not in stripped:
                continue
            key, raw = stripped.split("=", 1)
            if key.strip() == name:
                return raw.strip().strip("\"'")
    return ""


def load_credentials() -> tuple[str, str]:
    """Return (api_key, voice_id) or raise CredentialUnavailable."""
    api_key = load_env_value("ELEVENLABS_API_KEY")
    voice_id = load_env_value("ELEVENLABS_TTS_VOICE_ID")
    if api_key and voice_id:
        return api_key, voice_id
    missing = []
    if not api_key:
        missing.append("ELEVENLABS_API_KEY")
    if not voice_id:
        missing.append("ELEVENLABS_TTS_VOICE_ID")
    raise CredentialUnavailable(
        "ElevenLabs credential unavailable: " + ", ".join(missing)
    )


def el_tts_request(
    text: str,
    api_key: str,
    voice_id: str,
    model: str,
    timeout: float = 60.0,
) -> bytes:
    """POST one TTS request; return raw audio bytes."""
    url = f"{TTS_URL}/{voice_id}?output_format={OUTPUT_FORMAT}"
    body = json.dumps({"text": text, "model_id": model}).encode()
    request = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "xi-api-key": api_key,
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def el_tts_with_backoff(
    text: str,
    api_key: str,
    voice_id: str,
    model: str,
    max_retries: int = 6,
) -> bytes:
    """el_tts_request + exponential backoff on 429/5xx and transport."""
    delay = 1.0
    for attempt in range(max_retries):
        try:
            return el_tts_request(text, api_key, voice_id, model)
        except urllib.error.HTTPError as exc:
            if exc.code in (401, 403):
                raise CredentialUnavailable(
                    f"ElevenLabs auth rejected (http {exc.code})"
                ) from exc
            if exc.code in (402, 429):
                try:
                    detail = exc.read().decode("utf-8", "replace")[:500]
                except OSError:
                    detail = ""
                if exc.code == 402 or "quota_exceeded" in detail:
                    raise GenerationFailed(
                        f"quota exhausted (http {exc.code})"
                    ) from exc
            if exc.code == 429 or 500 <= exc.code < 600:
                retry_after = exc.headers.get("Retry-After")
                try:
                    pause = float(retry_after) if retry_after else delay
                except ValueError:
                    pause = delay
                time.sleep(min(max(pause, 0.5), 60.0))
                delay = min(delay * 2, 60.0)
                continue
            raise GenerationFailed(f"http {exc.code}") from exc
        except (urllib.error.URLError, TimeoutError) as exc:
            time.sleep(delay)
            delay = min(delay * 2, 60.0)
            if attempt == max_retries - 1:
                raise GenerationFailed(
                    f"transport: {exc.__class__.__name__}"
                ) from exc
    raise GenerationFailed("retries exhausted")


def fetch_subscription(api_key: str, timeout: float = 30.0) -> dict:
    """Return ElevenLabs subscription quota fields ({} on failure)."""
    request = urllib.request.Request(
        SUBSCRIPTION_URL,
        headers={"xi-api-key": api_key},
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
        return {}
    return {
        "tier": payload.get("tier"),
        "character_count": payload.get("character_count"),
        "character_limit": payload.get("character_limit"),
    }


def write_pcm_wav(pcm: bytes, dst: Path) -> float:
    """Wrap s16le mono PCM in a wav header; return duration seconds."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(dst), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(pcm)
    with wave.open(str(dst), "rb") as handle:
        return round(handle.getnframes() / handle.getframerate(), 3)


def read_ljspeech(metadata_path: Path) -> list[tuple[str, str]]:
    """Return sorted (clip_id, normalized_text) from LJSpeech metadata."""
    rows: list[tuple[str, str]] = []
    with metadata_path.open() as handle:
        for line in handle:
            parts = line.rstrip("\n").split("|")
            if len(parts) < 2:
                continue
            clip_id = parts[0].strip().lower()
            text = (parts[2] if len(parts) > 2 else "").strip()
            if not text:
                text = parts[1].strip()
            if clip_id and text:
                rows.append((clip_id, text))
    rows.sort()
    return rows


def load_done_state(
    journal_path: Path, manifest_path: Path, errors_path: Path
) -> tuple[set, set, list[dict]]:
    """Return (done_ids, done_text_hashes, journal_rows)."""
    done_ids: set = set()
    done_texts: set = set()
    journal_rows: list[dict] = []
    for path in (journal_path, manifest_path):
        if not path.is_file():
            continue
        for row in read_jsonl(path):
            row_id = row.get("id")
            if row_id:
                done_ids.add(row_id)
            text = row.get("text", "")
            if text:
                done_texts.add(text_sha256(text))
            if path == journal_path:
                journal_rows.append(row)
    if errors_path.is_file():
        for row in read_jsonl(errors_path):
            row_id = row.get("id")
            if row_id:
                done_ids.add(row_id)
    return done_ids, done_texts, journal_rows


def repair_manifest_from_journal(
    manifest_path: Path, journal_rows: list[dict]
) -> int:
    """Re-append journal rows missing from the manifest; return count."""
    manifest_ids = set()
    if manifest_path.is_file():
        manifest_ids = {r.get("id") for r in read_jsonl(manifest_path)}
    missing = [r for r in journal_rows if r.get("id") not in manifest_ids]
    if missing:
        with manifest_path.open("a") as handle:
            for row in missing:
                handle.write(json.dumps(row, ensure_ascii=False) + "\n")
    return len(missing)


def acquire_lock(out_dir: Path):
    """Exclusive non-blocking flock; None when another run holds it."""
    handle = (out_dir / LOCK_NAME).open("w")
    try:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        handle.close()
        return None
    return handle


def record_spend(
    out_dir: Path,
    api_key: str,
    utterances: int,
    chars: int,
    note: str,
) -> dict:
    """Append a spend checkpoint entry and rewrite the spend file."""
    sub = fetch_subscription(api_key)
    remaining = None
    count = sub.get("character_count")
    limit = sub.get("character_limit")
    if isinstance(count, int) and isinstance(limit, int):
        remaining = limit - count
    entry = {
        "at": utc_now(),
        "note": note,
        "utterances_done": utterances,
        "chars_billed_local": chars,
        "el_tier": sub.get("tier"),
        "el_character_count": count,
        "el_character_limit": limit,
        "el_quota_remaining": remaining,
    }
    path = out_dir / SPEND_NAME
    try:
        payload = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        payload = {"history": []}
    payload["history"].append(entry)
    payload["latest"] = entry
    path.write_text(json.dumps(payload, indent=1) + "\n")
    return entry


def run_verify(out_dir: Path, tools_dir: Path) -> int:
    """Run verify_pairs.py on the manifest; return its exit code."""
    cmd = [
        sys.executable,
        str(tools_dir / "verify_pairs.py"),
        "--manifest",
        str(out_dir / MANIFEST_NAME),
        "--out",
        str(out_dir / VERIFIED_NAME),
        "--stats",
        str(out_dir / VERIFY_STATS_NAME),
    ]
    proc = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=7200,
        check=False,
    )
    for line in proc.stdout.splitlines():
        print(f"  [verify] {line}", flush=True)
    if proc.returncode == 3:
        print(
            "  [verify] Deepgram credential unavailable; deferred",
            file=sys.stderr,
        )
    elif proc.returncode not in (0, 1):
        print(
            f"  [verify] exited {proc.returncode}: "
            f"{proc.stderr.strip()[:200]}",
            file=sys.stderr,
        )
    return proc.returncode


def refresh_quarantine(out_dir: Path) -> int:
    """Rebuild el_quarantine.jsonl from current verify failures."""
    verified_path = out_dir / VERIFIED_NAME
    if not verified_path.is_file():
        return 0
    quarantine_path = out_dir / QUARANTINE_NAME
    prior = {}
    if quarantine_path.is_file():
        for row in read_jsonl(quarantine_path):
            prior[row.get("id")] = row.get("quarantined_at")
    rows = []
    for row in read_jsonl(verified_path):
        if row.get("bucket") != BUCKET or row.get("pass"):
            continue
        reason = row.get("score_error") or (
            f"wer {row.get('wer')} > 0.1 "
            f"(strict {row.get('wer_strict')}, "
            f"spoken {row.get('wer_spoken')})"
        )
        rows.append(
            {
                "id": row.get("id"),
                "text": row.get("text"),
                "wav": row.get("wav"),
                "wer": row.get("wer"),
                "wer_strict": row.get("wer_strict"),
                "wer_spoken": row.get("wer_spoken"),
                "dg_transcript": row.get("dg_transcript"),
                "reason": reason,
                "quarantined_at": prior.get(row.get("id")) or utc_now(),
            }
        )
    write_jsonl(quarantine_path, rows)
    return len(rows)


def build_row(clip_id: str, text: str, audio: bytes, out_dir: Path) -> dict:
    """Write one wav and return its manifest/journal row."""
    wav_rel = f"el_audio/{clip_id}.wav"
    wav_path = out_dir / wav_rel
    dur_s = write_pcm_wav(audio, wav_path)
    return {
        "id": clip_id,
        "text": text,
        "wav": wav_rel,
        "source": f"elevenlabs-api:{DEFAULT_MODEL}",
        "dur_s": dur_s,
        "bucket": BUCKET,
        "format": OUTPUT_FORMAT,
        "sha256": sha256_file(wav_path),
        "voice": VOICE_LABEL,
        "chars": len(text),
        "generated_at": utc_now(),
    }


def append_line(path: Path, row: dict) -> None:
    """Append one jsonl row with flush+fsync (crash-safe resume)."""
    with path.open("a") as handle:
        handle.write(json.dumps(row, ensure_ascii=False) + "\n")
        handle.flush()
        os.fsync(handle.fileno())


def log_error(errors_path: Path, clip_id: str, text: str, error: str) -> None:
    """Record a permanent (non-retryable) generation failure."""
    append_line(
        errors_path,
        {
            "id": clip_id,
            "text": text,
            "error": error,
            "at": utc_now(),
        },
    )


def parse_args() -> argparse.Namespace:
    """Define the CLI."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--metadata", type=Path, default=DEFAULT_METADATA)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument("--max-utterances", type=int, default=2000)
    parser.add_argument("--max-chars", type=int, default=500_000)
    parser.add_argument("--checkpoint-every", type=int, default=250)
    parser.add_argument("--concurrency", type=int, default=2)
    parser.add_argument("--sleep", type=float, default=0.4)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--quota-floor-chars", type=int, default=25_000)
    parser.add_argument(
        "--dry",
        action="store_true",
        help="plan only; no network, no writes",
    )
    parser.add_argument(
        "--skip-verify",
        action="store_true",
        help="generate only; no Deepgram checkpoints",
    )
    return parser.parse_args()


def main() -> int:
    """Generate batch-1 EL corpus with verify + spend checkpoints."""
    args = parse_args()
    out_dir: Path = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    tools_dir = Path(__file__).resolve().parent
    journal_path = out_dir / JOURNAL_NAME
    manifest_path = out_dir / MANIFEST_NAME
    errors_path = out_dir / ERRORS_NAME

    if not args.metadata.is_file():
        print(f"missing metadata: {args.metadata}", file=sys.stderr)
        return 2

    done_ids, done_texts, journal_rows = load_done_state(
        journal_path, manifest_path, errors_path
    )
    repaired = repair_manifest_from_journal(manifest_path, journal_rows)
    if repaired:
        print(f"manifest repaired from journal: {repaired} row(s)")

    lj_rows = read_ljspeech(args.metadata)
    plan: list[tuple[str, str]] = []
    chars_planned = 0
    for clip_id, text in lj_rows:
        if clip_id in done_ids or text_sha256(text) in done_texts:
            continue
        if len(plan) >= args.max_utterances:
            break
        if chars_planned + len(text) > args.max_chars:
            break
        plan.append((clip_id, text))
        chars_planned += len(text)

    print(f"ljspeech rows: {len(lj_rows)}; done: {len(done_ids)}")
    print(f"planned: {len(plan)} utterances (~{chars_planned} chars)")
    if args.dry:
        print("dry run: no network calls made, nothing written")
        return 0
    if not plan:
        print("nothing to do: plan is empty")
        return 0

    try:
        api_key, voice_id = load_credentials()
    except CredentialUnavailable as exc:
        print(str(exc), file=sys.stderr)
        return 3

    lock = acquire_lock(out_dir)
    if lock is None:
        print(
            "another el_generate run holds the lock; refusing to "
            "duplicate EL generation",
            file=sys.stderr,
        )
        return 4

    workers = max(1, min(args.concurrency, MAX_CONCURRENCY))
    started = utc_now()
    start_ts = time.monotonic()
    generated = 0
    failed = 0
    chars_billed = 0
    seconds_audio = 0.0
    since_verify = 0
    stop_early = ""

    baseline = record_spend(out_dir, api_key, 0, 0, "batch start")
    remaining = baseline.get("el_quota_remaining")
    if remaining is not None and remaining < args.quota_floor_chars:
        print(f"quota floor at start ({remaining} chars); stopping")
        return 5
    print(
        f"EL quota: used={baseline.get('el_character_count')} "
        f"limit={baseline.get('el_character_limit')} "
        f"remaining={remaining}"
    )

    with ThreadPoolExecutor(max_workers=workers) as pool:
        pending = set()
        iterator = iter(plan)
        exhausted = False
        while True:
            while not exhausted and len(pending) < workers * 4:
                try:
                    clip_id, text = next(iterator)
                except StopIteration:
                    exhausted = True
                    continue
                future = pool.submit(
                    el_tts_with_backoff,
                    text,
                    api_key,
                    voice_id,
                    args.model,
                )
                future.spark_meta = (clip_id, text)
                pending.add(future)
            if not pending:
                break
            done, pending = wait(pending, return_when=FIRST_COMPLETED)
            for future in done:
                clip_id, text = future.spark_meta
                try:
                    audio = future.result()
                except CredentialUnavailable as exc:
                    print(str(exc), file=sys.stderr)
                    stop_early = "credential rejected mid-run"
                    pending.clear()
                    break
                except GenerationFailed as exc:
                    failed += 1
                    reason = str(exc)
                    print(f"  [fail] {clip_id}: {reason}", flush=True)
                    if reason.startswith("quota exhausted"):
                        stop_early = reason
                        break
                    if reason.startswith("http 4"):
                        log_error(errors_path, clip_id, text, reason)
                    continue
                row = build_row(clip_id, text, audio, out_dir)
                append_line(journal_path, row)
                append_line(manifest_path, row)
                generated += 1
                chars_billed += len(text)
                seconds_audio += row["dur_s"]
                since_verify += 1
                if generated % 25 == 0:
                    rate = generated / max(time.monotonic() - start_ts, 1)
                    print(
                        f"generated {generated}/{len(plan)} "
                        f"({rate * 60:.0f}/min, {chars_billed} chars)",
                        flush=True,
                    )
                if since_verify >= args.checkpoint_every:
                    if not args.skip_verify:
                        run_verify(out_dir, tools_dir)
                        n_quar = refresh_quarantine(out_dir)
                        print(f"  [quarantine] {n_quar} row(s)")
                    entry = record_spend(
                        out_dir, api_key, generated, chars_billed,
                        f"checkpoint {generated}",
                    )
                    rem = entry.get("el_quota_remaining")
                    if (
                        rem is not None
                        and rem < args.quota_floor_chars
                    ):
                        stop_early = f"quota floor ({rem} chars left)"
                    since_verify = 0
            if stop_early:
                print(f"stopping early: {stop_early}")
                break

    if since_verify and not args.skip_verify:
        run_verify(out_dir, tools_dir)
        n_quar = refresh_quarantine(out_dir)
        print(f"  [quarantine] {n_quar} row(s)")
    final_spend = record_spend(
        out_dir, api_key, generated, chars_billed, "batch stop"
    )

    elapsed = time.monotonic() - start_ts
    verify_stats = {}
    verify_path = out_dir / VERIFY_STATS_NAME
    if verify_path.is_file():
        try:
            verify_stats = json.loads(verify_path.read_text())
        except json.JSONDecodeError:
            verify_stats = {}
    quarantine_path = out_dir / QUARANTINE_NAME
    n_quarantine = (
        len(read_jsonl(quarantine_path)) if quarantine_path.is_file() else 0
    )
    stats = {
        "started_at": started,
        "finished_at": utc_now(),
        "elapsed_s": round(elapsed, 1),
        "generated_this_run": generated,
        "failed_this_run": failed,
        "stop_early": stop_early or None,
        "minutes_generated_this_run": round(seconds_audio / 60.0, 2),
        "chars_billed_local_this_run": chars_billed,
        "utterances_per_minute": round(generated / max(elapsed, 1) * 60, 1),
        "quarantined_total": n_quarantine,
        "verify": {
            "total_pairs": verify_stats.get("total_pairs"),
            "scored_pairs": verify_stats.get("scored_pairs"),
            "passed": verify_stats.get("passed"),
            "pass_rate": verify_stats.get("pass_rate"),
            "wer_mean": verify_stats.get("wer_mean"),
            "wer_max": verify_stats.get("wer_max"),
        },
        "spend": final_spend,
    }
    stats_path = out_dir / GEN_STATS_NAME
    stats_path.write_text(json.dumps(stats, indent=2) + "\n")
    print(f"stats: {stats_path}")
    print(
        f"done: {generated} generated, {failed} failed, "
        f"{stats['minutes_generated_this_run']} min audio, "
        f"{chars_billed} chars billed"
    )
    lock.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
