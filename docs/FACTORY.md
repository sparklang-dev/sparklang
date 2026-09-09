# Spark factory documentation (hub)

Engineer map for the **Spark / SparkLang** SPARK_BC factory on
[sparklang.dev](https://sparklang.dev/). Does **not** reimplement
SGD, attention, or serve APIs — links code + makefile targets.
**Never** claims beat Claude. **Never** trains on the RTX PRO 6000.

Reproduction story: [SPARK_BUILDER.md](SPARK_BUILDER.md).
**Diagrams:** [DIAGRAMS.md](DIAGRAMS.md) — tool map, shadows, LLM
assist vs deterministic SoT.
**AI model aspects (L):** [MODEL_ASPECTS.md](MODEL_ASPECTS.md) —
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
| **Diagrams (tools + LLM)** | [DIAGRAMS.md](DIAGRAMS.md) | [/docs/diagrams.html](/docs/diagrams.html) |
| Compile / assemble | [COMPILE.md](COMPILE.md) | [/docs/compile.html](/docs/compile.html) |
| Decompile / dump / inspect | [DECOMPILE.md](DECOMPILE.md) | [/docs/decompile.html](/docs/decompile.html) |
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

## Sibling factory lanes (do not steal)

| Lane | Scope | Docs stance |
|------|-------|-------------|
| **D** | Attention train/serve math | **Merged** (#28) — layer-0 attn; [ATTENTION_FORWARD.md](ATTENTION_FORWARD.md) / [SPARK_BUILDER.md](SPARK_BUILDER.md) |
| **E** | Claude eval harness | **Merged** — see [EVAL.md](EVAL.md) |
| **F** | Scale fixtures / dim knobs | **Merged** — see [TRAIN_LOOP.md](TRAIN_LOOP.md) / `spark-sgd-proof-scale` |
| **G** | Serve HTTP/API | **Merged** — see [SERVE.md](SERVE.md) / `make spark-serve-api` |
| **H** | Website + factory docs | **Merged** (#23/#25) — this hub + [DIAGRAMS.md](DIAGRAMS.md) |
| **I** | SDK / IDE / GUI pack | **Merged** (#24) — `make sdk-pack`; K enhances helpers overlay |
| **J** | Decompile research / captures | **Merged** (#26) + research expand — [DECOMPILE.md](DECOMPILE.md) + [research/LLM_DECOMPILE.md](research/LLM_DECOMPILE.md) (DecompAI / LLM4Decompile / EmergentMind / Quarkslab article + RE category / Plain English overview); flow diagrams also in [DIAGRAMS.md](DIAGRAMS.md) |
| **K** | Helpers / shadows / kit | **Merged** (#27) — [TOOLS_HELPERS.md](TOOLS_HELPERS.md) |
| **M** | Owned spark-coder TinyCoder | **Merged** (#30) — tiny CI + opt-in **large** (`--scale large` / `make spark-coder-train-large`); [SPARK_CODER.md](SPARK_CODER.md) |
| **L** | AI model aspects (senses + behaviors) | **Merged** (#29) — [MODEL_ASPECTS.md](MODEL_ASPECTS.md); eyes stub only |

## Honesty bar

- Multi-outer CPU SGD + layer-0 attn train + MLP0 serve + frozen
  eval — **yes** on tip (D #28).
- Owned TinyCoder (`make spark-coder-train`) — **yes** (M #30).
- Ears/speaking language surface + companions — **yes** (dry/live gated).
- Eyes / vision runtime — **no** (planned stub only).
- Owned TinyCoder tiny (CI) + large opt-in — **yes** (M); still not Claude.
- Beat Claude — **no**.
- Multi-layer / RoPE / production attn decode — **no** (layer-0
  last-query MHA only).
- RTX PRO **6000** train — **never** (voice-only).
- RTX **5090** — OK for factory / coder GPU train when used.
