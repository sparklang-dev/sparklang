# Voice corpus EL — batch-1 generation checkpoint (2026-09-10)

Owner directive chain: "we use EL voice and Deepgram to improve it" → the
merged distill pipeline (PR #58) inventoried + verified all existing
EL/Rachel audio at **25 clips / 1.11 min**; TTS distillation wants ~5–10 h.
This lane generates the corpus at scale from LJSpeech-1.1 texts with the
existing ElevenLabs Rachel voice, verified as-you-go with Deepgram.

Tool: `tools/voice-distill/el_generate.py` (this branch). Data lives
untracked under `data/voice/distill/` in the `sparklang-wt-el-corpus`
worktree (data/ is intentionally uncommitted; only `*.wav` is gitignored —
pathspec-disciplined commits, nothing under data/ was added).

## Batch-1 totals

| Metric | Value |
| --- | --- |
| Utterances generated | **2,000** (0 failed, 0 retried-permanent) |
| Source texts | LJSpeech-1.1 `metadata.csv`, normalized field, id order |
| Gross audio | **180.7 min** (3.01 h) |
| Local characters billed | **206,052** |
| Wall time | 38.7 min (51.6 utt/min incl. verify checkpoints) |
| Voice / model | Rachel (`ELEVENLABS_TTS_VOICE_ID`) / `eleven_flash_v2_5` |
| Format | `pcm_22050` → 22050 Hz mono s16 wav (lossless, no mp3 transcode) |

Corpus state after batch-1 (seed 25 bench clips + 4 smoke + 2,000 batch):

- **2,029 manifest rows**, 182.2 min gross
- **Verified clean: 1,664 rows (82.0%) ≈ 152.3 min (2.54 h)**
- Quarantined: **365 rows** (`el_quarantine.jsonl`, with reasons)

## Verification (Deepgram nova-3, cache-incremental, every 250)

Final `verify_stats.json`: pass **1,664/2,029 (0.8201)** at wer ≤ 0.1
(min of strict + spoken normalizations); WER mean 0.0513, median 0.0.
Batch-1 ljspeech rows only: 1,639/2,004 pass (81.8%).

Quarantine WER spread: **276** in (0.1, 0.25] (borderline), **75** in
(0.25, 0.5], **14** above 0.5. Dominant failure mode is **ASR-side
fragment ambiguity**, not bad audio: LJSpeech contains mid-sentence
fragments, and Deepgram drops/swaps leading function words on them
("has never been surpassed." → "Never been surpassed.", than/then).
This mirrors the known seed borderline (`hold-04`, dropped leading
"If"). The 14 high-WER rows are the ones worth eyeballing before any
re-generation consideration.

**Batch-2 text-selection recommendation:** prefer full-sentence LJSpeech
rows (filter: ≥6 words, starts with capital, ends with terminal punct)
to lift pass rate and clean-audio yield per billed character.

## Spend checkpoint (ElevenLabs subscription API)

| Field | Value |
| --- | --- |
| Tier | pro |
| character_count at stop | **778,036** / 878,796 limit |
| Batch-1 API-char consumption | **65,141** (7.4% of cycle limit) |
| Effective billing rate | **0.316 API-chars per local char** (Flash v2.5 half-credit) |
| Quota remaining | **100,760 API-chars** ≈ ~3,090 utterances at observed rate |

Full history in `data/voice/distill/el_spend_checkpoint.json`
(start / every 250 / stop). Local chars are the conservative upper
bound; the API counter is authoritative and grew slower throughout.

## ETA to full 13,100

- Remaining: 11,100 utterances ≈ 1.14M local chars ≈ **~361k API-chars**
  at the observed 0.316 rate — **exceeds the 100.8k remaining this
  cycle** (~3,090 utterances fit). Full completion needs the next
  billing cycle(s) or a plan change — an owner-visible decision.
- Wall-clock at observed rate: ~39 min per 2,000-utterance batch →
  ~3.6 h total for the remaining 11,100, quota permitting.
- Yield vs target: 5 h clean needs ~1,960 more utterances (fits this
  cycle); 10 h clean needs ~5,930 more (spans cycles).
- Gross audio at 13,100 would be ~19.7 h; clean at current pass rate
  ~16 h — comfortably above the 5–10 h goal, so the owner may stop
  earlier.

## EL-lane coordination

- No other live EL audio generation on the box (pgrep clean at start).
- The EL receptionist lane (`data/el-pairs.jsonl` in voicecore
  worktrees) remains **TEXT-only** (103 + 25 rows; no audio) — no
  duplication; nothing to supplement.
- Lock file (`.el_generate.lock`) refuses duplicate concurrent runs;
  released at exit.

## Resume / next batch

`python3 tools/voice-distill/el_generate.py --max-utterances N` — the
append-only `el_generated.jsonl` journal + manifest make re-runs
skip completed ids/texts; verification is cache-incremental
(`dg_cache.json`). Batch-2+ is a separate owner-visible decision.

## PR / merge state

- PR: https://github.com/sparklang-dev/sparklang/pull/61
  ("voice-distill: EL corpus generator + batch-1 checkpoint")
- CI `sparkbc`: **pass** (18m24s) on the generator commit; report
  commit re-triggers CI — merge per merge authority v3 once green.
- Committed: `tools/voice-distill/el_generate.py` + this report only.
