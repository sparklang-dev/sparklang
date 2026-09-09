# Spark voice surface

AI voice **listen/speak (STT/TTS)**, **reviewer**, **coder (codifer)**,
**copier**, **written voice models**, and **PSTN** (off by default).
Asm: `asm/voice_ops.s`. Companions: `./spark-stt-tts`, `./spark-pstn-dial`.

Spark stays a generic language; optional vendor voice ids are config only.

## Syntax

```
listen "input.wav" -> transcript
listen -> user                 # --live: mic (arecord)
speak "Hello" -> "out.wav"
speak reply -> "out.wav"       # text from last_val
speak with model NAME

voice review PATH_OR_ID -> report
voice code request "..." -> spark_or_asm
voice copy from SRC to DST -> voice_model
voice model write NAME spec { ... } -> path
voice model load NAME -> model

voice pstn status -> st
voice pstn dial "+1…" -> call
voice pstn hangup "CALL_ID"
```

## Live STT / TTS (`listen` / `speak`)

`--dry-run` / `make test` stay **offline** (stub transcript + tiny WAV
marker). `--live` forks `./spark-stt-tts` — real WAV I/O, mic, synth,
or HTTP vendors when explicitly gated on.

| Mode | Behavior |
|------|----------|
| Dry | Stub transcript; `write_stub_wav` honors `speak … -> "path"` (default `spark-out.wav`) |
| Live listen file | Open RIFF/WAVE; sidecar `.intent.txt` / `.txt`, or `SPARK_STT_CMD`, or local **openai-whisper**, or HTTP if net on |
| Live listen bare | `--mic` → `arecord` (S16_LE 16 kHz mono); then same STT path |
| Live speak | Built-in PCM synthesizer → real 16-bit WAV; or `SPARK_TTS_CMD`; or HTTP if net on; optional `aplay` |

### Network vendors — OFF by default

| Gate | Enables |
|------|---------|
| `SPARK_STT_NET=1` | HTTP STT via `SPARK_STT_URL` |
| `SPARK_TTS_NET=1` | HTTP TTS via `SPARK_TTS_URL` |
| `SPARK_SPEECH_NET=1` | Both STT + TTS net |

URL set without the gate → **exit 2** (fail closed; no silent vendor call).
Bearer: `SPARK_STT_KEY` / `SPARK_TTS_KEY` / `OPENAI_API_KEY` (never printed).

```bash
make                                    # builds spark-stt-tts
./spark --dry-run examples/voice_turn.spark   # offline
./spark --live examples/voice_live.spark      # local sidecar + synth

# Optional vendor (explicit):
export SPARK_SPEECH_NET=1
export SPARK_STT_URL=http://127.0.0.1:9/v1/audio/transcriptions
export SPARK_TTS_URL=http://127.0.0.1:9/v1/audio/speech
```

Local engines without vendors: `SPARK_STT_CMD` / `SPARK_TTS_CMD`
(shell; `%i` input path, `%o` output path), or **openai-whisper**
(`tiny.en` default; `SPARK_WHISPER_MODEL`; `SPARK_STT_WHISPER=0` to
disable). Play after speak: `SPARK_TTS_PLAY=1` or companion `--play`.

## Reviewer

Opens wav/ogg path (fixture: `examples/fixtures/audio/sample_review.wav`).
**Asm** parses RIFF/WAVE + PCM: sample rate, channels, bits, peak,
silence frames, clip hits, crude SNR hint. Emits structured JSON
(`byte_parsed:true`) — not fake metrics. Optional intent consistency
uses dry STT stub vs fixture intent.

```bash
./spark --dry-run examples/voice_reviewer.spark
```

## Coder (codifer)

`voice code request "…"` writes real `out/voice_codegen.spark` (or
`.s` notes if request mentions `.s`) that calls listen / classify /
ask / speak — runnable by the VM.

```bash
./spark --dry-run examples/voice_coder.spark
```

## Copier → written voice model

Extracts PCM feature coeffs into:

```
out/voice_models/<name>/manifest.json
out/voice_models/<name>/features.bin
```

Written model documents timbre/prosody params Spark understands.
Optional `brand_voice_id` in manifest (vendor TTS profile id)
is **config only** — not a live PSTN path.

Vendor **neural** clone (ElevenLabs/etc.) is outside this artifact;
the written model is fully loadable without stubbing “copied”.

```bash
./spark --dry-run examples/voice_copy.spark
```

## Overlay speak on a text-only model

`model train … method "spark_reply_pack"` stores spoken scripts in
`replies.json` even when the **base has no voice**. Spark `speak reply`
uses the pack; this is **not** neural TTS / voice-GPU training.
Inventable speak lines still need `sot_ref` (see
[MODEL_TRAINING.md](MODEL_TRAINING.md)).

```bash
./spark --dry-run examples/model_train_reply.spark
```

## Written AI voice models

```
voice model write NAME spec { … } -> path
voice model load NAME -> model
speak with model NAME
```

Templates: `templates/voice_models/`. Artifacts under
`out/voice_models/`.

## PSTN — capability on, default OFF

| Gate | Required for live dial |
|------|------------------------|
| `spark.toml` `[pstn] enabled=false` | documented default |
| Env `SPARK_PSTN=1` | yes |
| CLI `--pstn-live` (with `--live`) | yes |
| Allowlist | Placeholders `+15555550100` / `+15555550101`, or `SPARK_PSTN_ALLOW` |
| Telnyx | `TELNYX_API_KEY`, `TELNYX_CONNECTION_ID`, `SPARK_PSTN_FROM` |

### Divert / CARRIER_DIVERT

While a carrier-divert guard file (e.g. `SPARK_PSTN_GUARD_JSON`) has
`mode=failover` with `applied_dids`, live dial to those **guarded DIDs**
is refused (**exit 4**). Documented placeholders stay allowlisted.
Operator override
(only when explicitly enabled): `SPARK_PSTN_OVERRIDE_DIVERT=1`.

Also honors `SPARK_PSTN_CARRIER_DIVERT` / `SPARK_PSTN_REFUSE_LIVE_INJECT`
in combination with the ledger map.

### Dry-run / make test

`--dry-run` never forks `spark-pstn-dial`. Emits
`claimed:false`. `make test` / `make voice-test` prove default-off.

### Enable recipe

```bash
# 1) Env + Telnyx
export SPARK_PSTN=1
export SPARK_PSTN_FROM=+1YOUR_TN
export TELNYX_API_KEY=…
export TELNYX_CONNECTION_ID=…

# 2) Live Spark mode + PSTN flag (not dry-run)
./spark --live --pstn-live examples/voice_pstn.spark

# Dial only allowlisted placeholders unless SPARK_PSTN_ALLOW lists more
# voice pstn dial "+15555550100" -> call
```

### Default proof

```bash
./spark --dry-run examples/voice_pstn.spark   # claimed:false
./spark-pstn-dial --to +15555550100          # exit ≠ 0 (no gates)
```

## Files

| Path | Role |
|------|------|
| `asm/voice_ops.s` | review/code/copy/model/pstn |
| `tools/voice/spark_pstn_dial.c` | gated Telnyx dial/hangup |
| `examples/voice_*.spark` | dry-run demos |
| `templates/voice_models/` | manifest skeleton |
| `spark.toml` `[pstn]` | enabled=false |

## Production gaps (honest — not sold as telephony)

Spark voice is a **language/demo surface**, not a production call center.

**Not shipped as production:** barge-in; end-of-utterance / silence;
latency budgets; call state machine (transfer / hold / hangup / voicemail /
DTMF / STT retry); named STT/TTS/telephony adapter contracts; multi-call
concurrency model.

Until those land, keep voice **optional / gated** on the marketing site.
See [ADOPTION_BAR.md](ADOPTION_BAR.md) and [ROADMAP.md](ROADMAP.md).
