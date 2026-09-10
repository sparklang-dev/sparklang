#!/usr/bin/env python3
"""Inventory ElevenLabs (Rachel-voice) audio+text pairs on this box.

Searches voicecore/callsback worktrees for:

- ``bench/tts/script.jsonl`` + ``bench/tts/reference-el/`` clip dirs
  (mp3 + ulaw renderings of a frozen script), and
- ``data/el-pairs*.jsonl`` text-capture files (text-only, no audio).

Audio clips are content-hash deduplicated (worktrees hold identical
copies), converted to 22050 Hz mono wav under
``data/voice/distill/el_audio/``, and recorded in
``data/voice/distill/el_manifest.jsonl`` as
``{id, text, wav, source, dur_s, ...}`` rows. Aggregate counts land in
``data/voice/distill/el_stats.json``.

READ-ONLY on every source repo: nothing outside the sparklang
``data/voice/distill/`` output tree is ever written.
"""

from __future__ import annotations

import argparse
import datetime
import glob
import hashlib
import json
import subprocess
import sys
import wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from dg_common import read_jsonl, write_jsonl  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT_DIR = REPO_ROOT / "data" / "voice" / "distill"

DEFAULT_TTS_GLOBS = (
    "/home/mike/workspaces/*/bench/tts",
    "/home/mike/workspaces/.wt-*/bench/tts",
    "/home/mike/workspaces/voicecore/.wt-*/bench/tts",
)
DEFAULT_PAIRS_GLOBS = (
    "/home/mike/workspaces/*/data/el-pairs*.jsonl",
    "/home/mike/workspaces/.wt-*/data/el-pairs*.jsonl",
    "/home/mike/workspaces/voicecore/.wt-*/data/el-pairs*.jsonl",
)

SAMPLE_RATE = 22050
# Voice identity per bench/tts/render_references.py: a single
# ELEVENLABS_TTS_VOICE_ID ("Rachel") rendered with eleven_flash_v2_5.
VOICE_LABEL = "rachel-elevenlabs-flash-v2.5"


def sha256_file(path: Path) -> str:
    """Stream a file's sha256 without loading it whole."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def convert_to_wav(src: Path, dst: Path) -> None:
    """Decode any ffmpeg-supported audio to 22050 Hz mono PCM wav."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(src),
            "-ar",
            str(SAMPLE_RATE),
            "-ac",
            "1",
            "-sample_fmt",
            "s16",
            str(dst),
        ],
        check=True,
    )


def wav_duration_s(path: Path) -> float:
    """Duration of a PCM wav via the stdlib wave module."""
    with wave.open(str(path), "rb") as handle:
        return handle.getnframes() / handle.getframerate()


def find_tts_dirs(extra_globs: list[str]) -> list[Path]:
    """Expand the default + extra globs into existing bench/tts dirs."""
    seen: set[Path] = set()
    dirs: list[Path] = []
    for pattern in (*DEFAULT_TTS_GLOBS, *extra_globs):
        for match in sorted(glob.glob(pattern)):
            path = Path(match).resolve()
            if path.is_dir() and path not in seen:
                seen.add(path)
                dirs.append(path)
    return dirs


def find_pairs_files(extra_globs: list[str]) -> list[Path]:
    """Expand globs into existing el-pairs*.jsonl files."""
    seen: set[Path] = set()
    files: list[Path] = []
    for pattern in (*DEFAULT_PAIRS_GLOBS, *extra_globs):
        for match in sorted(glob.glob(pattern)):
            path = Path(match).resolve()
            if path.is_file() and path not in seen:
                seen.add(path)
                files.append(path)
    return files


def collect_clips(
    tts_dirs: list[Path], out_dir: Path, force: bool
) -> tuple[list[dict], dict]:
    """Dedupe and convert EL clips; return (manifest rows, stats)."""
    rows: list[dict] = []
    seen_hashes: dict[str, str] = {}
    per_source: dict[str, int] = {}
    per_bucket: dict[str, int] = {}
    dupes = 0
    missing_audio: list[str] = []
    audio_out = out_dir / "el_audio"

    for tts_dir in tts_dirs:
        script_path = tts_dir / "script.jsonl"
        ref_dir = tts_dir / "reference-el"
        if not script_path.is_file() or not ref_dir.is_dir():
            continue
        source_name = str(tts_dir.parent.parent)
        for item in read_jsonl(script_path):
            clip_id = item.get("id")
            text = item.get("text", "")
            bucket = item.get("bucket", "unknown")
            if not clip_id or not text:
                continue
            mp3 = ref_dir / f"{clip_id}.mp3"
            ulaw = ref_dir / f"{clip_id}.ulaw"
            src = mp3 if mp3.is_file() else (ulaw if ulaw.is_file() else None)
            if src is None:
                missing_audio.append(f"{source_name}:{clip_id}")
                continue
            clip_hash = sha256_file(src)
            if clip_hash in seen_hashes:
                dupes += 1
                continue
            seen_hashes[clip_hash] = clip_id
            wav_path = audio_out / f"{clip_id}.wav"
            if force or not wav_path.is_file():
                convert_to_wav(src, wav_path)
            dur_s = round(wav_duration_s(wav_path), 3)
            rows.append(
                {
                    "id": clip_id,
                    "text": text,
                    "wav": str(wav_path.relative_to(out_dir)),
                    "source": str(src),
                    "dur_s": dur_s,
                    "bucket": bucket,
                    "format": src.suffix.lstrip("."),
                    "sha256": clip_hash,
                    "voice": VOICE_LABEL,
                }
            )
            per_source[source_name] = per_source.get(source_name, 0) + 1
            per_bucket[bucket] = per_bucket.get(bucket, 0) + 1

    rows.sort(key=lambda row: row["id"])
    stats = {
        "per_source": per_source,
        "per_bucket": per_bucket,
        "duplicate_clips_skipped": dupes,
        "script_rows_missing_audio": missing_audio,
    }
    return rows, stats


def summarize_pairs_files(pairs_files: list[Path]) -> dict:
    """Count text-only el-pairs rows (no audio attached)."""
    per_file: dict[str, int] = {}
    total = 0
    classes: dict[str, int] = {}
    for path in pairs_files:
        try:
            rows = read_jsonl(path)
        except (OSError, json.JSONDecodeError) as exc:
            per_file[f"{path} (unreadable: {exc.__class__.__name__})"] = 0
            continue
        per_file[str(path)] = len(rows)
        total += len(rows)
        for row in rows:
            cls = row.get("class", "unknown")
            classes[cls] = classes.get(cls, 0) + 1
    return {
        "files": per_file,
        "total_text_pairs": total,
        "per_class": classes,
        "note": "el-pairs rows are text captures (el_turn/our_turn); "
        "they carry no audio and are excluded from the wav manifest.",
    }


def main() -> int:
    """Inventory EL audio+text pairs and write manifest + stats."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=DEFAULT_OUT_DIR,
        help="output dir (default: data/voice/distill)",
    )
    parser.add_argument(
        "--extra-tts-glob",
        action="append",
        default=[],
        help="additional glob(s) for bench/tts dirs",
    )
    parser.add_argument(
        "--extra-pairs-glob",
        action="append",
        default=[],
        help="additional glob(s) for el-pairs*.jsonl files",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="re-convert wavs even if they already exist",
    )
    args = parser.parse_args()

    out_dir: Path = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    tts_dirs = find_tts_dirs(args.extra_tts_glob)
    pairs_files = find_pairs_files(args.extra_pairs_glob)
    rows, clip_stats = collect_clips(tts_dirs, out_dir, args.force)
    pairs_summary = summarize_pairs_files(pairs_files)

    manifest_path = out_dir / "el_manifest.jsonl"
    write_jsonl(manifest_path, rows)

    total_dur = sum(row["dur_s"] for row in rows)
    stats = {
        "generated_at": datetime.datetime.now(
            datetime.timezone.utc
        ).isoformat(),
        "total_clips": len(rows),
        "total_minutes": round(total_dur / 60.0, 2),
        "total_seconds": round(total_dur, 1),
        "distinct_voices": sorted({row["voice"] for row in rows}),
        "sample_rate_hz": SAMPLE_RATE,
        "tts_dirs_searched": [str(d) for d in tts_dirs],
        "text_only_pairs": pairs_summary,
        **clip_stats,
    }
    stats_path = out_dir / "el_stats.json"
    stats_path.write_text(json.dumps(stats, indent=2) + "\n")

    print(f"manifest: {manifest_path} ({len(rows)} clips)")
    print(f"stats:    {stats_path}")
    print(
        f"totals:   {len(rows)} clips, {stats['total_minutes']} min, "
        f"{clip_stats['duplicate_clips_skipped']} dupes skipped"
    )
    print(f"text-only el-pairs rows: {pairs_summary['total_text_pairs']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
