# voice-distill — EL inventory + Deepgram verify/judge harness

Data pipeline for the voice distillation effort: ElevenLabs (EL) voice
audio and Deepgram transcription are **teachers** used to inventory,
verify, and grade voice data for SparkLang's owned ears (STT) and voice
(TTS). This directory is **data tooling only** — no model code, no
training, no website changes.

All tools are Python 3.12 stdlib-only (plus `ffmpeg`/`ffprobe` on PATH
for audio decode). Outputs land under `data/voice/distill/` (gitignored
data tree — never commit it).

## Tools

### `el_inventory.py` — find + canonicalize EL audio/text pairs

Searches the box for EL/Rachel-voice material (read-only on every
source):

- `bench/tts/script.jsonl` + `bench/tts/reference-el/` dirs across
  voicecore/callsback worktrees (mp3 + ulaw renderings of a frozen
  25-line script), and
- `data/el-pairs*.jsonl` text captures (counted as text-only; they
  carry no audio).

Clips are sha256-deduplicated (worktrees hold identical copies),
decoded to 22050 Hz mono wav in `data/voice/distill/el_audio/`, and
written to `data/voice/distill/el_manifest.jsonl`
(`{id, text, wav, source, dur_s, bucket, sha256, voice}`). Aggregates
land in `data/voice/distill/el_stats.json`.

```bash
python3 tools/voice-distill/el_inventory.py            # inventory
python3 tools/voice-distill/el_inventory.py --force    # re-convert
```

### `dg_transcribe.py` — Deepgram batch transcription CLI

Transcribes every `wav` in a manifest jsonl via the Deepgram REST API
(default model `nova-3`, `smart_format=true`), writing
`dg_transcript` / `dg_confidence` / `dg_model` back into the manifest.
Results are cached in `dg_cache.json` keyed by `model:sha256`, so
re-runs never re-bill unchanged audio.

```bash
python3 tools/voice-distill/dg_transcribe.py \
    --manifest data/voice/distill/el_manifest.jsonl --dry   # plan
python3 tools/voice-distill/dg_transcribe.py \
    --manifest data/voice/distill/el_manifest.jsonl         # run
```

### `verify_pairs.py` — flag bad EL generations

Transcribes each EL clip (cached batch path) and scores transcript vs
known script text with stdlib WER/CER. Pass = `wer <= 0.1`, where
`wer` is the min of two documented normalizations:

- **strict** — lowercase, punctuation stripped;
- **spoken-form** — additionally collapses spelled-letter runs
  (`M-A-X-A-L-T` → `maxalt`), digit-word runs (`five one five` →
  `515`), and order-number merges (`B-Z 55001` → `bz55001`), matching
  Deepgram `smart_format` output conventions.

Both scores are kept on every row (`wer_strict`, `wer_spoken`, `wer`,
`cer_*`). Outputs `el_verified.jsonl` + `verify_stats.json`.

```bash
python3 tools/voice-distill/verify_pairs.py --dry   # plan
python3 tools/voice-distill/verify_pairs.py         # run
```

### `dg_roundtrip_judge.py` — independent TTS roundtrip grader

Reusable harness for the TTS roundtrip gate: given a jsonl of
`{id, text, wav}` candidates (SparkLang's own TTS output), transcribe
with Deepgram and report per-pair + aggregate WER/CER/pass. The base
build currently self-grades with its own STT — this judge is the
independent upgrade; the training phase wires it in. Importable:

```python
from dg_roundtrip_judge import judge_pairs
verdicts = judge_pairs(rows, transcribe_fn=my_transcriber)
```

```bash
python3 tools/voice-distill/dg_roundtrip_judge.py \
    --pairs candidates.jsonl --out verdicts.jsonl
```

## Credentials

- `DEEPGRAM_API_KEY` — read from the process environment, or as a
  `key=value` line from `~/.config/voicecore/.env` (loader convenience).
  The key is held in memory only: never printed, logged, written to
  disk, or committed. If no key is found the tools exit 3 with
  `Deepgram credential unavailable` and write nothing.
- No ElevenLabs key is used here — this lane generates **no** new EL
  audio (inventory + verification only).

## Current stats (2026-09-10 run)

Inventory (`el_stats.json`):

- **25 unique clips**, 1.11 minutes total, 22050 Hz mono wav
- 300 duplicate clips skipped (13 identical worktree copies)
- 1 distinct voice: `rachel-elevenlabs-flash-v2.5`
- buckets: greeting / price-info / spell-back / closing /
  hold-transfer-text (5 each)
- source: `callsback-a105-lw-cents` `bench/tts/reference-el` (canonical
  first-seen; all worktree copies hash-identical)

Verification (`verify_stats.json`, Deepgram `nova-3`):

- **pass rate 25/25 (1.0)** at `wer <= 0.1`; strict-only 21/25 (0.84)
- WER mean 0.0036, median 0.0, max 0.0909; 24/25 exact matches
- the 4 strict-only failures are `spell-back` clips — smart_format
  collapsing artifacts, not bad audio (all pass spoken-form)
- borderline: `hold-04` wer 0.0909 (Deepgram drops leading "If")

Gap assessment: ~1.1 minutes of clean verified single-voice audio vs
the ~5–10 h typically wanted for TTS training — the EL generation lane
needs to keep running; this pipeline re-verifies new drops via re-run
(cache makes re-runs incremental).
