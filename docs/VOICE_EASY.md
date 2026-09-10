# Voice easy — real open-weight STT / TTS in 3 steps

Piece-of-cake path for Spark voice: **real ears** (speech-to-text)
and a **real voice** (text-to-speech), built on best-in-class open
weights — Whisper-class ASR and Kokoro-class TTS — self-hosted,
running offline after a one-time fetch, with **no API keys**.

These models are **pretrained by their upstream authors, not by us**:

| Piece | Model | License | Size on disk |
|-------|-------|---------|--------------|
| STT (ears) | `faster-whisper` CTranslate2 port of OpenAI **Whisper large-v3-turbo** (real lane) / `tiny` (CI smoke) | MIT | 1.6 GB / 75 MB |
| TTS (voice) | **Kokoro-82M** via `kokoro-onnx` (`kokoro-v1.0.onnx` + `voices-v1.0.bin`) | Apache-2.0 | 338 MB |

Weights are fetched once into `models/spark-voice-stt/` and
`models/spark-voice-tts/` (both gitignored) by a pinned,
checksummed fetcher, then every wrapper path runs **fully offline**
(`HF_HUB_OFFLINE=1`, `local_files_only=True`, no network).

## 3 steps

```bash
# 1) Fetch the real weights once (pinned sha256 + size per file)
make voice-easy-fetch
# same as: ./spark-voice fetch   (or python3 tools/spark-voice/fetch_models.py)

# 2) Eval + roundtrip on real speech (CI smoke scale)
make voice-easy

# 3) Status — which weights are present, sizes, devices
./spark-voice status
```

`./spark-voice env` prints the environment check (weights presence,
LJSpeech presence, devices). No secrets are read or printed.

## Honest evaluation (measured, not asserted)

The eval lane scores the real pipeline on **held-out clips from
LJSpeech-1.1** (public-domain audiobook speech, single speaker,
English; `data/voice/`, gitignored, fetched separately). Text is
normalized (case/punctuation/whitespace) before scoring; WER and CER
are computed in-repo with stdlib Levenshtein — no vendor metric
package, no file-size "gates", no train-set accuracy.

Measured on this repo's dev box (CPU, int8, 2026-09-10):

| Eval | Models | n | WER | CER |
|------|--------|---|-----|-----|
| STT on held-out LJSpeech clips | Whisper large-v3-turbo | 50 | **2.67%** | **2.82%** |
| TTS → STT roundtrip | Kokoro-82M (`af_heart`) → Whisper large-v3-turbo | 20 | **1.67%** | **2.08%** |
| STT smoke (CI scale) | Whisper tiny | 8 | 4.66% | 1.42% |
| Roundtrip smoke (CI scale) | Kokoro-82M → Whisper tiny | 4 | 1.09% | 0.68% |

Reproduce:

```bash
make voice-easy-fetch
./spark-voice easy --scale large --device cpu   # writes out/voice_easy/eval/eval_report.json
```

The roundtrip row is the honest intelligibility signal: Kokoro
synthesizes real held-out LJSpeech transcripts it never saw as audio,
Whisper transcribes the synthesized speech back, and we score the
text against the reference transcript.

## Scales

`tiny` / `large` now mean **eval-subset size + model variant** —
nothing else:

| Scale | STT variant | STT clips | Roundtrip utterances | Use |
|-------|-------------|-----------|----------------------|-----|
| **tiny** (default) | Whisper `tiny` | 8 | 4 | CI smoke, laptops |
| **large** (opt-in) | Whisper `large-v3-turbo` | 50 | 20 | Real measurement |

```bash
./spark-voice easy --scale tiny  --device cpu   # CI smoke
./spark-voice easy --scale large --device cpu   # full numbers
```

## Devices (hard rule)

CPU int8 is the default everywhere. GPU eval is allowed **only** on a
consumer GPU via `CUDA_VISIBLE_DEVICES=1` (RTX 5090). The reserved
voice-serving GPU (RTX PRO 6000) is **never** touched — `device.py`
refuses it in every path.

| Flag / env | Meaning |
|------------|---------|
| `--device auto\|cpu\|5090` | auto prefers CPU int8; 5090 only when free |
| `--scale tiny\|large` | eval subset + STT variant (see above) |
| `--dry` | plan only — no eval, no synthesis |
| `VOICE_SCALE=large` | same as `--scale large` when flag omitted |

## No training here

These are pretrained upstream weights. `spark-voice train` is an
honest no-op stub that points at `fetch` + `easy`; there is nothing
to train in this lane and no train@ unit is involved.

## CLI surface

```bash
./spark-voice env      # environment check (no secrets)
./spark-voice fetch    # pinned, checksummed weight download
./spark-voice easy     # STT eval + TTS→STT roundtrip
./spark-voice prove    # roundtrip only
./spark-voice status   # weights present? sizes? eval report?
```

When weights are not fetched, `easy`/`prove` **skip loudly**
(`status: skipped_no_weights`) and tell you to run `fetch` — they
never fall back to a fake.

## Make / CI

```bash
make voice-easy-fetch  # one-time real weight download
make voice-easy        # dry tiny happy path (CI-safe)
make test-voice-easy   # unit tests always run; integration skips
                       # loudly without weights (GHA green either way)
make voice-easy-large  # opt-in real measurement (needs fetch first)
```

## Scope

| Claim | Status |
|-------|--------|
| Real open-weight STT (Whisper-class) | **yes** — measured WER above |
| Real open-weight TTS (Kokoro-class) | **yes** — measured roundtrip above |
| Self-hosted, offline after fetch, no API keys | **yes** |
| CI green without multi-GB downloads | **yes** (unit tests + loud skips) |
| Frontier/proprietary parity | **not claimed** — numbers above are the claim |
| Multi-speaker / multilingual eval | Out of scope (LJSpeech is one English speaker) |
