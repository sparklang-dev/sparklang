"""Prep tiny fixture audio + text for voice-easy train / prove."""

from __future__ import annotations

import json
import math
import struct
import wave
from pathlib import Path
from typing import Any


# Stable demo phrases — owned fixtures, not scraped vendor corpora.
BASE_PHRASES = [
    "spark listen dry",
    "washer cycle done",
    "dryer thirty minutes",
    "check card balance",
    "store hours today",
    "speak reply please",
    "train voice easy",
    "owned weights only",
]


def _write_tone_wav(
    path: Path,
    *,
    freq_hz: float,
    seconds: float = 0.35,
    rate: int = 16000,
) -> None:
    """Write a mono S16_LE tone (deterministic fixture audio)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    n = max(1, int(rate * seconds))
    frames = bytearray()
    for i in range(n):
        t = i / float(rate)
        amp = 0.35 * math.sin(2.0 * math.pi * freq_hz * t)
        sample = int(max(-1.0, min(1.0, amp)) * 32767)
        frames.extend(struct.pack("<h", sample))
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(rate)
        wf.writeframes(bytes(frames))


def audio_features(path: Path, *, bins: int = 8) -> list[float]:
    """Cheap PCM features — owned STT (not Mel / Whisper claim).

    Dominant-frequency estimate + energy bins so fixture tones
    stay linearly separable for the tiny head.
    """
    with wave.open(str(path), "rb") as wf:
        raw = wf.readframes(wf.getnframes())
        rate = int(wf.getframerate())
        width = int(wf.getsampwidth())
        ch = int(wf.getnchannels())
    if width != 2 or ch != 1 or not raw:
        return [0.0] * bins
    n = len(raw) // 2
    samples = struct.unpack("<%dh" % n, raw[: n * 2])
    # Zero-crossing rate → rough frequency (Hz).
    zc = 0
    for i in range(1, n):
        if (samples[i - 1] >= 0) != (samples[i] >= 0):
            zc += 1
    dur = n / float(rate)
    freq_hz = (zc / 2.0) / max(1e-6, dur)
    freq_norm = min(1.0, freq_hz / 800.0)
    # Energy bins across the clip.
    feats = [0.0] * bins
    feats[0] = freq_norm
    if bins > 1:
        feats[1] = math.sin(freq_norm * math.pi)
    if bins > 2:
        feats[2] = math.cos(freq_norm * math.pi)
    chunk = max(1, n // max(1, bins - 3))
    for b in range(3, bins):
        start = (b - 3) * chunk
        stop = min(n, start + chunk)
        if stop <= start:
            continue
        acc = 0.0
        for i in range(start, stop):
            acc += abs(samples[i]) / 32768.0
        feats[b] = acc / float(stop - start)
    return feats


def prep_fixtures(
    out_dir: Path,
    *,
    n_phrases: int = 6,
    bins: int = 8,
) -> dict[str, Any]:
    """Write wav+text pairs under out_dir; return manifest."""
    out_dir = Path(out_dir)
    audio_dir = out_dir / "audio"
    audio_dir.mkdir(parents=True, exist_ok=True)
    phrases = BASE_PHRASES[: max(1, min(n_phrases, len(BASE_PHRASES)))]
    # Expand for large scale by repeating with suffixes.
    while len(phrases) < n_phrases:
        base = BASE_PHRASES[len(phrases) % len(BASE_PHRASES)]
        phrases.append("%s %d" % (base, len(phrases)))
    pairs: list[dict[str, Any]] = []
    for i, text in enumerate(phrases):
        # Distinct tones so STT features separate.
        freq = 220.0 + (i * 37.0)
        wav = audio_dir / ("utt_%02d.wav" % i)
        _write_tone_wav(wav, freq_hz=freq)
        txt = audio_dir / ("utt_%02d.txt" % i)
        txt.write_text(text + "\n", encoding="utf-8")
        feats = audio_features(wav, bins=bins)
        pairs.append(
            {
                "id": i,
                "text": text,
                "wav": str(wav.relative_to(out_dir)),
                "txt": str(txt.relative_to(out_dir)),
                "features": feats,
                "freq_hz": freq,
            }
        )
    manifest = {
        "profile": "spark-voice-easy",
        "n_pairs": len(pairs),
        "bins": bins,
        "rate": 16000,
        "pairs": pairs,
        "beats_claude": False,
        "never": "rtx-pro-6000",
        "note": "owned fixture tones + phrases — not vendor audio",
    }
    (out_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n",
        encoding="utf-8",
    )
    return manifest
