# Spark factory documentation (hub)

Engineer map for the **Spark / SparkLang** SPARK_BC factory on
[sparklang.dev](https://sparklang.dev/). Does **not** reimplement
SGD, attention, or serve APIs — links code + makefile targets.
**Never** claims beat Claude. **Never** trains on the RTX PRO 6000.

Reproduction story: [SPARK_BUILDER.md](SPARK_BUILDER.md).
**Diagrams:** [DIAGRAMS.md](DIAGRAMS.md) — tool map, shadows, LLM
assist vs deterministic SoT.
**AI model aspects:** [MODEL_ASPECTS.md](MODEL_ASPECTS.md) —
behaviors, ears/STT, eyes/vision, speaking/TTS, thinking, memory,
tools, train, eval, serve.
**AI knowledge hive:** [KNOWLEDGE.md](KNOWLEDGE.md) — engineer-grade
field explainers (transformers → safety) with original diagrams.

## Map (everything)

| Topic | Doc | Site |
|-------|-----|------|
| **AI knowledge hive** | [KNOWLEDGE.md](KNOWLEDGE.md) | [/docs/knowledge.html](/docs/knowledge.html) |
| **AI model aspects** | [MODEL_ASPECTS.md](MODEL_ASPECTS.md) | [/docs/model-aspects.html](/docs/model-aspects.html) |
| Voice / STT / TTS | [VOICE.md](VOICE.md) | [/docs/voice.html](/docs/voice.html) |
| **Voice ask (dump Q&A)** | [VOICE_ASK.md](VOICE_ASK.md) | [/docs/voice-ask.html](/docs/voice-ask.html) |
| **Voice easy train** | [VOICE_EASY.md](VOICE_EASY.md) | [/docs/voice-easy.html](/docs/voice-easy.html) |
| **Diagrams (tools + LLM)** | [DIAGRAMS.md](DIAGRAMS.md) | [/docs/diagrams.html](/docs/diagrams.html) |
| Compile / assemble | [COMPILE.md](COMPILE.md) | [/docs/compile.html](/docs/compile.html) |
| Decompile / dump / inspect | [DECOMPILE.md](DECOMPILE.md) | [/docs/decompile.html](/docs/decompile.html) |
| Decompile compete / scoreboard | [DECOMPILE_COMPETE.md](DECOMPILE_COMPETE.md) | [/docs/decompile-compete.html](/docs/decompile-compete.html) |
| LLM decompile research | [research/LLM_DECOMPILE.md](research/LLM_DECOMPILE.md) | [/docs/llm-decompile.html](/docs/llm-decompile.html) |
| Opcode ISA (TRAIN/STEP/…) | [SPARK_BC.md](SPARK_BC.md) | [/docs/spark-bc.html](/docs/spark-bc.html) |
| Build models + weights | [BUILD_MODELS.md](BUILD_MODELS.md) | [/docs/build-models.html](/docs/build-models.html) |
| Train loop (outer/inner) | [TRAIN_LOOP.md](TRAIN_LOOP.md) | [/docs/train-loop.html](/docs/train-loop.html) |
| Architecture pieces | [ARCHITECTURE.md](ARCHITECTURE.md) | [/docs/architecture.html](/docs/architecture.html) |
| **Weight gallery** | [WEIGHT_GALLERY.md](WEIGHT_GALLERY.md) | [/docs/weight-gallery.html](/docs/weight-gallery.html) |
| Attention / MLP honesty | [ATTENTION_FORWARD.md](ATTENTION_FORWARD.md) | [/docs/attention-forward.html](/docs/attention-forward.html) |
| Tokenizer / BPE | [TOKENIZER.md](TOKENIZER.md) | [/docs/tokenizer.html](/docs/tokenizer.html) |
| Serve forward + HTTP | [SERVE.md](SERVE.md) | [/docs/serve.html](/docs/serve.html) |
| Eval harness | [EVAL.md](EVAL.md) | [/docs/eval.html](/docs/eval.html) |
| **Spark coder (owned)** | [SPARK_CODER.md](SPARK_CODER.md) | [/docs/spark-coder.html](/docs/spark-coder.html) |
| Makefile targets | [SPARKBC_MAKE.md](SPARKBC_MAKE.md) | [/docs/sparkbc-make.html](/docs/sparkbc-make.html) |
| Tools & helpers | [TOOLS_HELPERS.md](TOOLS_HELPERS.md) | [/docs/tools-helpers.html](/docs/tools-helpers.html) |
| Methods vs OpenBin | [METHODS_OPENBIN.md](METHODS_OPENBIN.md) | [/docs/methods-openbin.html](/docs/methods-openbin.html) |
| CI + Pages how-to | [CI_PAGES.md](CI_PAGES.md) | [/docs/ci-pages.html](/docs/ci-pages.html) |
| Full factory E2E | [SPARK_BUILDER.md](SPARK_BUILDER.md) | [/docs/spark-builder.html](/docs/spark-builder.html) |
| Adoption honesty | [ADOPTION_BAR.md](ADOPTION_BAR.md) | [/docs/adoption-bar.html](/docs/adoption-bar.html) |

## Quick start (stranger with the repo)

```bash
make spark-bootstrap spark
make test-sparkbc
make sparkbc-e2e
make spark-sgd-proof
make spark-eval
make docs-check
```

## Factory feature status

| Feature | Docs stance |
|---------|-------------|
| Attention train/serve (layer-0) | **On tip** — [ATTENTION_FORWARD.md](ATTENTION_FORWARD.md) / [SPARK_BUILDER.md](SPARK_BUILDER.md) |
| Eval harness | **On tip** — [EVAL.md](EVAL.md) |
| Scale fixtures / dim knobs | **On tip** — [TRAIN_LOOP.md](TRAIN_LOOP.md) / `spark-sgd-proof-scale` |
| Serve HTTP/API | **On tip** — [SERVE.md](SERVE.md) / `make spark-serve-api` |
| Website + factory docs | **On tip** — this hub + [DIAGRAMS.md](DIAGRAMS.md) |
| SDK / IDE / GUI pack | **On tip** — `make sdk-pack`; helpers overlay in [TOOLS_HELPERS.md](TOOLS_HELPERS.md) |
| Decompile / RE research | **On tip** — [DECOMPILE.md](DECOMPILE.md) + [research/LLM_DECOMPILE.md](research/LLM_DECOMPILE.md); scoreboard in [DECOMPILE_COMPETE.md](DECOMPILE_COMPETE.md) |
| Helpers / shadows / kit | **On tip** — [TOOLS_HELPERS.md](TOOLS_HELPERS.md) |
| Owned spark-coder (TinyCoder) | **On tip** — tiny CI + opt-in **large**; [SPARK_CODER.md](SPARK_CODER.md) |
| Model aspects (senses) | **On tip** — [MODEL_ASPECTS.md](MODEL_ASPECTS.md); eyes stub only |
| Grounding / anti-guess | **On tip** — `./spark-ground`; [knowledge/SAFETY_LIMITS.md](knowledge/SAFETY_LIMITS.md) |
| Voice ask / voice easy | **On tip** — [VOICE_ASK.md](VOICE_ASK.md) / [VOICE_EASY.md](VOICE_EASY.md) |
| Local analyze loop | **On tip** — `./helpers/spark-analyze`; [METHODS_OPENBIN.md](METHODS_OPENBIN.md) |
| Weight gallery | **On tip** — [WEIGHT_GALLERY.md](WEIGHT_GALLERY.md) |

## Honesty bar

- Multi-outer CPU SGD + layer-0 attn train + MLP0 serve + frozen
  eval — **yes** on tip.
- Owned TinyCoder (`make spark-coder-train`) — **yes** (tiny CI +
  large opt-in); still not Claude.
- Ears/speaking language surface + companions — **yes** (dry/live gated).
- Voice easy owned STT/TTS train (`make voice-easy`) — **yes**.
- Eyes / vision runtime — **no** (planned stub only).
- Beat Claude — **no**.
- Multi-layer / RoPE / production attn decode — **no** (layer-0
  last-query MHA only).
- GPU train policy: prefer **RTX 5090** (or CPU). Do **not** place
  Spark train jobs on the voice-reserved RTX PRO **6000**.
