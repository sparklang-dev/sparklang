#!/usr/bin/env python3
"""Shared helpers for the voice-distill data pipeline.

Deepgram REST access, credential loading (env-var only, never printed),
transcript normalization, and stdlib WER/CER scoring.

Credential policy: the Deepgram API key is read from the
``DEEPGRAM_API_KEY`` environment variable, or (as a loader convenience)
from ``key=value`` lines in ``~/.config/voicecore/.env``. The key is
never printed, logged, written to disk, or committed.
"""

from __future__ import annotations

import json
import os
import re
import urllib.error
import urllib.request
from pathlib import Path

DEFAULT_MODEL = "nova-3"
LISTEN_URL = "https://api.deepgram.com/v1/listen"
DEFAULT_ENV_FILES = (Path.home() / ".config" / "voicecore" / ".env",)

_PUNCT_RE = re.compile(r"[^\w\s']")
_SPACE_RE = re.compile(r"\s+")

_DIGIT_WORDS = {
    "zero": "0",
    "one": "1",
    "two": "2",
    "three": "3",
    "four": "4",
    "five": "5",
    "six": "6",
    "seven": "7",
    "eight": "8",
    "nine": "9",
    "oh": "0",
}


class CredentialUnavailable(RuntimeError):
    """Raised when no Deepgram credential can be located."""


def load_deepgram_key(env_files: tuple[Path, ...] = DEFAULT_ENV_FILES) -> str:
    """Return the Deepgram API key without ever printing it.

    Search order: ``DEEPGRAM_API_KEY`` in the process environment, then
    ``key=value`` lines in each file in ``env_files`` (first hit wins).
    Raises CredentialUnavailable if no key is found anywhere.
    """
    key = os.environ.get("DEEPGRAM_API_KEY", "").strip()
    if key:
        return key
    for path in env_files:
        try:
            lines = path.read_text().splitlines()
        except OSError:
            continue
        for line in lines:
            stripped = line.strip()
            if not stripped or stripped.startswith("#") or "=" not in stripped:
                continue
            name, value = stripped.split("=", 1)
            if name.strip() == "DEEPGRAM_API_KEY":
                value = value.strip().strip("\"'")
                if value:
                    return value
    searched = ", ".join(str(p) for p in env_files)
    raise CredentialUnavailable(
        "Deepgram credential unavailable: DEEPGRAM_API_KEY not set and "
        f"not found in: {searched}"
    )


def transcribe_wav(
    wav_path: Path,
    api_key: str,
    model: str = DEFAULT_MODEL,
    timeout: float = 60.0,
    extra_params: dict[str, str] | None = None,
) -> dict:
    """Transcribe one wav file via the Deepgram REST API.

    Returns {"transcript": str, "confidence": float|None,
             "duration_s": float|None, "model": str}.
    Raises urllib.error.URLError / HTTPError on transport failure.
    """
    params = {
        "model": model,
        "smart_format": "true",
        "punctuate": "true",
    }
    if extra_params:
        params.update(extra_params)
    query = "&".join(f"{k}={v}" for k, v in params.items())
    url = f"{LISTEN_URL}?{query}"
    body = Path(wav_path).read_bytes()
    request = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Token {api_key}",
            "Content-Type": "audio/wav",
        },
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        payload = json.loads(response.read().decode("utf-8"))
    result = payload.get("results", {})
    channels = result.get("channels") or []
    alternatives = channels[0].get("alternatives") if channels else []
    best = alternatives[0] if alternatives else {}
    metadata = payload.get("metadata", {})
    return {
        "transcript": best.get("transcript", ""),
        "confidence": best.get("confidence"),
        "duration_s": metadata.get("duration"),
        "model": model,
    }


def normalize_text(text: str) -> str:
    """Lowercase, strip punctuation (keep apostrophes), collapse spaces."""
    lowered = text.lower()
    no_punct = _PUNCT_RE.sub(" ", lowered)
    return _SPACE_RE.sub(" ", no_punct).strip()


def normalize_spoken_form(text: str) -> str:
    """Align spelled-out reference text with ASR smart-format output.

    ASR services with smart formatting collapse spelled sequences, so a
    fair comparison normalizes the reference the same way:

    - runs of single letters join: "M-A-X-A-L-T" -> "maxalt"
    - runs of digit words collapse: "five one five" -> "515"
    - a joined-letters token followed by a digit run merges:
      "B-Z 55001" -> "bz55001" (order-number style)

    Single-letter tokens that stand alone ("a", "I") stay words.
    """
    tokens = normalize_text(text).split()
    merged: list[tuple[str, str]] = []
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if token in _DIGIT_WORDS:
            digits = []
            while index < len(tokens) and tokens[index] in _DIGIT_WORDS:
                digits.append(_DIGIT_WORDS[tokens[index]])
                index += 1
            merged.append(("".join(digits), "digits"))
        elif len(token) == 1 and token.isalpha():
            letters = []
            while (
                index < len(tokens)
                and len(tokens[index]) == 1
                and tokens[index].isalpha()
            ):
                letters.append(tokens[index])
                index += 1
            if len(letters) >= 2:
                merged.append(("".join(letters), "letters"))
            else:
                merged.append((letters[0], "word"))
        else:
            merged.append((token, "word"))
            index += 1
    out: list[str] = []
    prev_kind = ""
    for token, kind in merged:
        if kind == "digits" and prev_kind == "letters" and out:
            out[-1] = out[-1] + token
            prev_kind = "letters"
            continue
        out.append(token)
        prev_kind = kind
    return " ".join(out)


def _levenshtein(ref: list, hyp: list) -> int:
    """Classic DP edit distance between two sequences."""
    if len(ref) < len(hyp):
        ref, hyp = hyp, ref
    previous = list(range(len(hyp) + 1))
    for i, ref_item in enumerate(ref, start=1):
        current = [i]
        for j, hyp_item in enumerate(hyp, start=1):
            cost = 0 if ref_item == hyp_item else 1
            current.append(
                min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost,
                )
            )
        previous = current
    return previous[-1]


def word_error_rate(
    reference: str, hypothesis: str, normalizer=normalize_text
) -> float:
    """WER on normalized text; 0.0 when both sides are empty."""
    ref_words = normalizer(reference).split()
    hyp_words = normalizer(hypothesis).split()
    if not ref_words:
        return 0.0 if not hyp_words else 1.0
    return _levenshtein(ref_words, hyp_words) / len(ref_words)


def char_error_rate(
    reference: str, hypothesis: str, normalizer=normalize_text
) -> float:
    """CER on normalized text (whitespace-collapsed characters)."""
    ref_chars = list(normalizer(reference))
    hyp_chars = list(normalizer(hypothesis))
    if not ref_chars:
        return 0.0 if not hyp_chars else 1.0
    return _levenshtein(ref_chars, hyp_chars) / len(ref_chars)


def best_error_rates(reference: str, hypothesis: str) -> dict:
    """Score under both normalizations and keep the kinder alignment.

    Returns strict (case/punct only) and spoken-form WER/CER plus the
    min of each. The min answers the verification question — "does the
    audio say what the text says?" — without penalizing transcript
    formatting conventions (spelled letters, digit runs).
    """
    wer_strict = word_error_rate(reference, hypothesis)
    cer_strict = char_error_rate(reference, hypothesis)
    wer_spoken = word_error_rate(
        reference, hypothesis, normalizer=normalize_spoken_form
    )
    cer_spoken = char_error_rate(
        reference, hypothesis, normalizer=normalize_spoken_form
    )
    return {
        "wer_strict": round(wer_strict, 4),
        "cer_strict": round(cer_strict, 4),
        "wer_spoken": round(wer_spoken, 4),
        "cer_spoken": round(cer_spoken, 4),
        "wer": round(min(wer_strict, wer_spoken), 4),
        "cer": round(min(cer_strict, cer_spoken), 4),
    }


def read_jsonl(path: Path) -> list[dict]:
    """Load a jsonl file into a list of dicts (skips blank lines)."""
    rows = []
    with Path(path).open() as handle:
        for line in handle:
            if line.strip():
                rows.append(json.loads(line))
    return rows


def write_jsonl(path: Path, rows: list[dict]) -> None:
    """Write dicts to a jsonl file, one JSON object per line."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")
