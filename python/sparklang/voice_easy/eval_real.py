"""Honest voice eval: real WER/CER on LJSpeech held-out clips.

Two measurements, both on real audio / real transcripts:

1. STT eval — transcribe held-out LJSpeech clips with the real
   Whisper lane and score word/character error rate against the
   published transcripts (normalized: lowercase, punctuation
   stripped, whitespace collapsed).
2. TTS → STT roundtrip — synthesize held-out LJSpeech transcripts
   with the real Kokoro lane, transcribe the audio back with
   Whisper, and score roundtrip WER/CER. This is a real
   intelligibility number, never a file-size check.

WER/CER are implemented here in stdlib Python (Levenshtein on
word/character sequences). No training happens anywhere in this
module — the models are pretrained open weights.
"""

from __future__ import annotations

import csv
import re
import string
from pathlib import Path
from typing import Any, Iterable

_REPO_ROOT = Path(__file__).resolve().parents[3]
LJSPEECH_ROOT = _REPO_ROOT / "data" / "voice" / "LJSpeech-1.1"

_PUNCT_TABLE = str.maketrans("", "", string.punctuation)
_WS_RE = re.compile(r"\s+")


def normalize_text(text: str) -> str:
    """Lowercase, strip punctuation, collapse whitespace."""
    out = str(text).lower().translate(_PUNCT_TABLE)
    return _WS_RE.sub(" ", out).strip()


def _levenshtein(a: list[Any], b: list[Any]) -> int:
    """Classic DP edit distance between two sequences."""
    if len(a) < len(b):
        a, b = b, a
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, start=1):
        cur = [i]
        for j, cb in enumerate(b, start=1):
            cost = 0 if ca == cb else 1
            cur.append(
                min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            )
        prev = cur
    return prev[-1]


def error_rate(ref: str, hyp: str, *, unit: str = "word") -> float:
    """WER (unit='word') or CER (unit='char') after normalization.

    Empty reference with empty hypothesis scores 0.0; empty
    reference with non-empty hypothesis scores 1.0.
    """
    ref_n = normalize_text(ref)
    hyp_n = normalize_text(hyp)
    if unit == "word":
        r: list[Any] = ref_n.split()
        h: list[Any] = hyp_n.split()
    elif unit == "char":
        r = list(ref_n)
        h = list(hyp_n)
    else:
        raise ValueError("unit must be word|char (got %r)" % unit)
    if not r:
        return 0.0 if not h else 1.0
    return _levenshtein(r, h) / float(len(r))


def wer(ref: str, hyp: str) -> float:
    """Word error rate between reference and hypothesis."""
    return error_rate(ref, hyp, unit="word")


def cer(ref: str, hyp: str) -> float:
    """Character error rate between reference and hypothesis."""
    return error_rate(ref, hyp, unit="char")


def load_ljspeech(
    root: Path | None = None,
) -> list[dict[str, Any]]:
    """Load LJSpeech metadata as sorted [{id, wav, text}] rows."""
    root = Path(root) if root else LJSPEECH_ROOT
    meta = root / "metadata.csv"
    if not meta.is_file():
        raise FileNotFoundError(
            "LJSpeech metadata.csv missing under %s — extract "
            "data/voice/LJSpeech-1.1.tar.bz2 first" % root
        )
    rows: list[dict[str, Any]] = []
    with meta.open(newline="", encoding="utf-8") as fh:
        for rec in csv.reader(fh, delimiter="|"):
            if len(rec) < 3:
                continue
            clip_id = str(rec[0]).strip()
            text = str(rec[2]).strip()  # normalized transcript col
            wav = root / "wavs" / ("%s.wav" % clip_id)
            if clip_id and text and wav.is_file():
                rows.append({"id": clip_id, "wav": wav, "text": text})
    rows.sort(key=lambda r: str(r["id"]))
    return rows


def held_out_subset(
    rows: list[dict[str, Any]], n: int
) -> list[dict[str, Any]]:
    """Deterministic held-out slice: the tail of the sorted corpus.

    We never train on LJSpeech, so the tail convention simply gives
    a stable, reproducible eval set that mirrors the classic
    train/val split point of LJSpeech-1.1.
    """
    if n <= 0:
        raise ValueError("subset size must be positive")
    if len(rows) < n:
        raise ValueError(
            "LJSpeech subset requested %d rows but only %d available"
            % (n, len(rows))
        )
    return rows[-n:]


def _mean(values: Iterable[float]) -> float:
    vals = list(values)
    return sum(vals) / float(len(vals)) if vals else 0.0


def run_stt_eval(
    *,
    n_clips: int,
    variant: str,
    device: str = "cpu",
    ljspeech_root: Path | None = None,
) -> dict[str, Any]:
    """Transcribe held-out LJSpeech clips; return WER/CER report."""
    from sparklang.voice_easy.stt_real import transcribe_wav

    rows = held_out_subset(load_ljspeech(ljspeech_root), n_clips)
    details: list[dict[str, Any]] = []
    for row in rows:
        result = transcribe_wav(
            row["wav"], variant=variant, device=device
        )
        details.append(
            {
                "id": row["id"],
                "ref": row["text"],
                "hyp": result["text"],
                "wer": round(wer(row["text"], result["text"]), 6),
                "cer": round(cer(row["text"], result["text"]), 6),
            }
        )
    return {
        "ok": True,
        "kind": "stt_eval",
        "dataset": "LJSpeech-1.1",
        "split": "held-out tail (sorted by clip id)",
        "n_clips": len(details),
        "stt_variant": variant,
        "device": device,
        "wer": round(_mean(d["wer"] for d in details), 6),
        "cer": round(_mean(d["cer"] for d in details), 6),
        "details": details,
    }


def run_roundtrip_eval(
    *,
    n_utts: int,
    stt_variant: str,
    device: str = "cpu",
    voice: str = "af_heart",
    out_dir: Path | None = None,
    ljspeech_root: Path | None = None,
) -> dict[str, Any]:
    """TTS real transcripts → STT the audio back → WER/CER report."""
    from sparklang.voice_easy.stt_real import transcribe_wav
    from sparklang.voice_easy.tts_real import speak

    rows = held_out_subset(load_ljspeech(ljspeech_root), n_utts)
    out_dir = (
        Path(out_dir)
        if out_dir
        else _REPO_ROOT / "out" / "voice_easy" / "roundtrip"
    )
    out_dir.mkdir(parents=True, exist_ok=True)
    details: list[dict[str, Any]] = []
    for row in rows:
        wav_path = out_dir / ("tts_%s.wav" % row["id"])
        synth = speak(row["text"], wav_path, voice=voice)
        back = transcribe_wav(
            wav_path, variant=stt_variant, device=device
        )
        details.append(
            {
                "id": row["id"],
                "ref": row["text"],
                "roundtrip_hyp": back["text"],
                "tts_wav": str(wav_path),
                "tts_seconds": synth["seconds"],
                "wer": round(wer(row["text"], back["text"]), 6),
                "cer": round(cer(row["text"], back["text"]), 6),
            }
        )
    return {
        "ok": True,
        "kind": "tts_stt_roundtrip",
        "dataset": "LJSpeech-1.1",
        "split": "held-out tail (sorted by clip id)",
        "n_utts": len(details),
        "tts_engine": "kokoro-onnx",
        "tts_voice": voice,
        "stt_variant": stt_variant,
        "device": device,
        "wer": round(_mean(d["wer"] for d in details), 6),
        "cer": round(_mean(d["cer"] for d in details), 6),
        "details": details,
    }
