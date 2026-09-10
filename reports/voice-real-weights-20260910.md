# Voice real weights — fake tone pipeline replaced with open-weight STT/TTS

**Date:** 2026-09-10 · **Owner directive (Michael, ~02:50 CT):** "no tiny
models and weights we need real ones the best" · "make the claims true" ·
"get rid of the stupid claude language".
**PR:** https://github.com/sparklang-dev/sparklang/pull/62 — **MERGED**
2026-09-10T10:51:08Z, merge commit `0ee5ea1269792bc9be492fde82bc8687b66e04a1`.

## What was fake (evidence)

The `python/sparklang/voice_easy/` pipeline was theater:

- **STT** was a 32-phrase **tone classifier** — 43.75% accuracy on
  synthetic sine tones, not speech.
- **TTS** emitted **identical 0.25 s sine WAVs** regardless of input text.
- The TTS "gate" was a **file-size check**, not intelligibility.
- `fixtures.py` synthesized tone WAVs (220+i×37 Hz) with canned phrases
  and called it training data.
- Committed "weights" under `models/spark-voice-easy/` parameterized this
  toy.

## What replaced it (real ears + real voice, open weights, offline)

| Piece | Model | License | Size on disk |
| --- | --- | --- | --- |
| STT (ears), real lane | faster-whisper / CTranslate2 **Whisper large-v3-turbo** | MIT | 1.6 GB (`models/spark-voice-stt/large-v3-turbo/`) |
| STT, CI smoke | faster-whisper **Whisper tiny** | MIT | 75 MB (`models/spark-voice-stt/tiny/`) |
| TTS (voice) | **Kokoro-82M** via `kokoro-onnx` 0.6.1 | Apache-2.0 | 338 MB (`models/spark-voice-tts/`: `kokoro-v1.0.onnx` 325,532,387 B + `voices-v1.0.bin` 28,214,398 B) |

- **Pretrained upstream weights — not trained by us.** No training was
  launched; no `train@` unit; GPU 0 (RTX PRO 6000) untouched. CPU int8 is
  the default; CUDA only via `CUDA_VISIBLE_DEVICES=1` (5090) if asked.
- Weights are **fetched once** by `tools/spark-voice/fetch_models.py`
  (pinned sha256 + byte size for all 11 files; `--check` verifies) into
  gitignored `models/spark-voice-stt/` / `models/spark-voice-tts/`, then
  the wrappers run **fully offline** (`HF_HUB_OFFLINE=1`,
  `local_files_only=True`, no network in wrapper paths). No API keys.
- `tts_real.py` is pure-stdlib at import time (`array` + `wave`; numpy
  only via kokoro's own returned arrays) so the module imports on a bare
  CI runner; integration tests skip loudly when deps/weights are absent.
- kokoro-onnx installed cleanly (`pip install --user faster-whisper
  kokoro-onnx` → 1.2.1 / 0.6.1); no fallback to piper was needed.

## Measured numbers (this box, CPU int8, 2026-09-10)

Held-out **LJSpeech-1.1** (tarball verified at 2,748,572,632 B, extracted
to gitignored `data/voice/LJSpeech-1.1/`; 13,100 clips; held-out = sorted
tail by clip id). WER/CER implemented in-repo, stdlib only, after
case/punctuation normalization.

| Eval | n | WER | CER |
| --- | --- | --- | --- |
| **STT, Whisper large-v3-turbo** | 50 clips | **2.67%** (0.026703) | **2.82%** (0.028172) |
| **TTS→STT roundtrip, Kokoro `af_heart` → large-v3-turbo** | 20 utts | **1.67%** (0.016667) | **2.08%** (0.020769) |
| STT smoke, Whisper tiny (CI scale) | 8 clips | 4.66% (0.046579) | 1.42% (0.014167) |
| Roundtrip smoke, Kokoro → tiny | 4 utts | 2.17% (0.021739) | 1.01% (0.010135) |

Reproduced twice: once on the branch and again on merged `main`
(`0ee5ea1`) with identical numbers. Canonical artifact:
`out/voice_easy/eval/eval_report.json` (holds the **latest** run — the
`make test-voice-easy` tiny dry-run overwrites it; regenerate the large
numbers with the command below).

Reproduce:

```
make voice-easy-fetch          # pinned, checksummed one-time download
./spark-voice easy --scale large --device cpu
# → out/voice_easy/eval/eval_report.json
```

## Claude scrub (owner: "get rid of the stupid claude language")

- Every `beats_claude` flag/key removed from code, JSON, safetensors
  metadata, and fixtures. Remaining repo hits are **regression guards
  only** (`assert 'beats_claude' not in …` in Makefile / test_dump.py /
  test_eval.py / test_spark_coder.py / test_gui_pack.py /
  test_weight_gallery.py / test_analyze.py, the refusal in
  `apply_step.py`, the `payload.pop("beats_claude", None)` in
  spark_coder/train.py) plus the two **scrubber janitors**
  (`tools/scrub_public_claims_leaks.py`, `scrub_changelog_operator_leaks.py`)
  whose job is matching removal patterns, and the functional Anthropic
  API model id `claude-3-5-haiku-latest` in `frontier_baseline.py`
  (an API identifier, not copy).
- `tools/spark-eval/claude_baseline.py` → **`frontier_baseline.py`**
  (`FRONTIER=off|auto|on`, `SPARK_EVAL_FRONTIER_*`, `--frontier` flag);
  Makefile `spark-eval-claude` → `spark-eval-frontier`; workflow step
  renamed. The baseline still calls the Anthropic Messages API only when
  a key already exists on the box; it never upgrades `claim` to a win.
- Site + docs reworded to **no-frontier-parity** framing; "Not
  ElevenLabs"-style vendor disclaimers replaced with "best-in-class open
  weights (Whisper-class ASR, Kokoro-class TTS), self-hosted, runs
  offline, no API keys". CHANGELOG entries reworded keeping
  measurement-only honesty. `docs/VOICE_EASY.md` rewritten with the
  measured numbers + licenses + fetch instructions; `make docs-html`
  regenerated.
- **DoD grep clean:** `grep -ri claude website/
  python/sparklang/voice_easy/ tools/spark-voice/` → no matches.
- Fixed on the way: main's own `tools/spark_analyze/test_analyze.py` was
  red on main (#68 scrubbed the source string but not the test
  assertion); this branch fixed the assertion. Main's spark-coder
  `weights.safetensors` still carried "does not beat Claude" in its
  `__metadata__.goal` — rewritten to "no frontier-parity claim" (tensor
  bytes unchanged, verified byte-identical; new sha256
  `959d1f5d4d192a7e4d9edbf5262b38c30c76bcf62e78d765e58ebad4fb72d8a8`
  repinned in `models/spark-coder/checkpoint.json`).

## Files changed (109 in the squashed PR)

- **Added:** `stt_real.py`, `tts_real.py`, `eval_real.py`,
  `tools/spark-voice/fetch_models.py`, `frontier_baseline.py`.
- **Deleted:** `fixtures.py`, `model.py`, `train.py`, `roundtrip.py`,
  all of `models/spark-voice-easy/` (fake weights), `claude_baseline.py`.
- **Rewritten:** `scales.py` (tiny/large = eval-subset size + model
  variant; fake dims/n_phrases/feat_bins gone), `pipeline.py`, `cli.py`
  (easy|fetch|train|prove|status|env; `train` is an honest no-train
  stub), `test_voice_easy.py` (31 tests: unit always-run + integration
  that skips loudly without weights/deps), `docs/VOICE_EASY.md`.
- **Kept:** `device.py` GPU-guard logic (never RTX PRO 6000).
- `.gitignore`: `data/`, `models/spark-voice-stt/`,
  `models/spark-voice-tts/`.
- Also scrubbed/reworded across `website/`, `docs/`, `Makefile`,
  `tools_loop.py`, `weight_gallery.py`, `voice_ask.py`,
  `spark_bc_gui/core.py`, `apply_step.py`, `decompile_bench.py`,
  `run_e2e_gate.sh`, decompile-scoreboard JSONs, spark-train-step.spark
  comment; weight-gallery catalog JSONs regenerated.

## Tests (all green on this box, rebased tree = merged content)

`make test-voice-easy` (31) · `test-sparkbc` · `sparkbc-e2e` ·
`spark-sgd-proof` (`no_frontier_parity_claim`) · `spark-eval` /
`test-spark-eval` (8) · `spark-eval-frontier`
(`skipped_no_credentials` — honest, no key) · `test-spark-coder` (12) ·
`test-spark-ask` (4) · `test-serve-api` · `tools-test` ·
`test-js-parity` · `test-sdk-pack` · `docs-check` (45 pages) ·
spark_analyze (4) · spark_bc_gui (11) · weight_gallery + sparkasm (12) ·
bc-dump. **CI:** PR run
[34466539002](https://github.com/sparklang-dev/sparklang/actions/runs/34466539002)
success; main post-merge run
[34468211645](https://github.com/sparklang-dev/sparklang/actions/runs/34468211645)
success. Checks API worked (no 403).

## Deploy status

- Merged to `main` at 2026-09-10T10:51:08Z; branch deleted (local +
  remote) per git hygiene.
- **Cloudflare Pages (sparklang.dev):** not yet reflecting the merge at
  report time (11:37 UTC, ~46 min). Pages deploys are Cloudflare-side
  and not observable via GitHub APIs from this box (no deployment
  records; check-runs list shows only the sparkbc workflow). Earlier
  merges today (#69) went live within ~20 min; this one is slower —
  possibly a Pages build queue. Verified merged `main` contains the new
  page (`website/docs/voice-easy.html` has the measured numbers), so the
  deploy is a matter of Pages catching up, not missing content. No
  wrangler/CF credentials were used and none were asked for.

## Honest limitations

- **Single-speaker English eval set** (LJSpeech-1.1 audiobook voice).
  Numbers do not transfer to accents, noise, telephony, or multi-speaker
  audio. 50 clips / 20 utts is a smoke-scale honest measurement, not a
  published benchmark run.
- **CPU int8 latency is seconds-scale** per clip/utterance; the large
  eval takes ~4–5 min wall-clock on this box. No GPU path was used or
  needed.
- **"Offline" means after the one-time fetch.** First run needs network
  for the pinned downloads; every run after is fully local.
- Roundtrip WER measures TTS→ASR intelligibility on clean studio-style
  speech; it is not a MOS naturalness score.
- Whisper tiny smoke numbers are CI-canary quality, not product claims.
- No parity claims vs frontier/proprietary services are made anywhere;
  the frontier baseline is measurement-only and off by default.

## Delivery incidents (resolved)

- Branch rebased twice as main moved (#63–#66, then #68–#70); conflicts
  resolved keeping main's functional changes and re-applying the scrub.
- 12 files initially written with CRLF line endings — converted to LF
  before merge.
- `website/downloads/sparklang-sdk-0.6.62.tar.gz` (untracked build
  artifact) was briefly staged by a bulk `git add -A` mid-rebase —
  removed from the commit before push; never merged.
- Untracked `spark-serve-ref` / `spark-voice-loop` binaries left alone
  as instructed.
