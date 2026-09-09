# Spark voice ask (binary / dump Q&A)

Speak to a **local** SPARK_BC dump or analysis folder —
ears (STT) → question → model → speaking (TTS).

Inspired by clear “ask the binary” product loops elsewhere;
**not** an OpenBin SaaS clone and **not** gated on OpenBin login.
OpenBin remains a separate research/lab note
([research/LLM_DECOMPILE.md](research/LLM_DECOMPILE.md)).

Dump / `--compile` / `--run-bc` stay SoT. **Never** 6000.
Does **not** beat Claude. No API keys in git.

Companions: `./spark-stt-tts` · brain: owned `spark-coder`
(TinyCoder) and/or dump-fact answers · map:
[MODEL_ASPECTS.md](MODEL_ASPECTS.md) · voice surface:
[VOICE.md](VOICE.md).

## Quick start

```bash
make helpers
make spark-stt-tts          # optional for live STT/TTS
# optional tiny brain:
make spark-coder-train

# Text (no mic) — dump facts / TinyCoder
./spark-ask docs/examples/spark-train-step.sparkbc \
  --text "What opcodes are in this dump?"

# Voice loop, offline CI (stub STT + stub WAV)
./spark-speak-ask docs/examples/spark-train-step.sparkbc --dry

# Voice loop, live mic + local synth (needs spark-stt-tts)
./spark-speak-ask docs/examples/spark-train-step.sparkbc --mic

# Analysis folder from project loop (sibling spark-analyze)
./spark-ask out/analyze/demo --text "How many opcodes?"
./helpers/spark-speak-ask out/analyze/demo --dry
```

Root `./spark-ask` and `./spark-speak-ask` are thin aliases of
`helpers/spark-ask` / `helpers/spark-speak-ask`.

## Modes

| Flag | Behavior |
|------|----------|
| `--text Q` | Skip mic; answer Q |
| `--voice` / `spark-speak-ask` | STT → answer → TTS |
| `--dry` | Fixture question + stub WAV (CI / no sidecar) |
| `--wav FILE` | Listen from RIFF/WAVE |
| `--mic` | `arecord` via `./spark-stt-tts` |
| `--out-wav PATH` | Write spoken answer |
| `--play` | `aplay` after live speak |
| `--weights PATH` | TinyCoder safetensors |
| `--json` | Machine-readable result |

## Brain honesty

1. **Dump facts** — opcodes, sha256, magic SPBC, TRAIN presence
   answered from decoded dump (preferred SoT).
2. **TinyCoder** — when `models/spark-coder/weights.safetensors`
   exists, inject dump excerpt + question; greedy generate.
3. **Weak / missing** — honesty footer: TinyCoder is **tiny**, not
   OpenBin-level RE Q&A, does **not** beat Claude. Prefer
   `dump.txt` / `ops.json`.

## STT / TTS gates

Same gates as [VOICE.md](VOICE.md):

| Gate | Meaning |
|------|---------|
| (default local) | `spark-stt-tts` PCM synth; whisper / `SPARK_STT_CMD` when available |
| `SPARK_STT_NET=1` + URL | HTTP STT |
| `SPARK_TTS_NET=1` + URL | HTTP TTS |
| `SPARK_SPEECH_NET=1` | Both |

URL without gate → fail closed (exit 2). Never print Bearer keys.

## Tests

```bash
make test-spark-ask
# or:
PYTHONPATH=python:tools python3 -m unittest \
  tools.spark_ask.test_voice_ask -v
```

## Grounding / anti-guess

Dump facts are the SoT for opcode / sha answers. For inventable
prices or free generate, use forced grounding — abstain unless
expect / fixture / dump match:

```bash
./spark-ground ask --prompt "…" --dump dump.txt \
  --candidate "…"   # miss → exit 2
make test-ground
```

See [knowledge/SAFETY_LIMITS.md](knowledge/SAFETY_LIMITS.md)
(Grounded generation / anti-guess). Recompile ≠ semantics.
Does **not** beat Claude.

## Related

- Loop UX: [/workflow.html](/workflow.html)
- Analyze project folder: `helpers/spark-analyze` (when present)
- [SPARK_CODER.md](SPARK_CODER.md) · [TOOLS_HELPERS.md](TOOLS_HELPERS.md)
- [knowledge/SAFETY_LIMITS.md](knowledge/SAFETY_LIMITS.md)
