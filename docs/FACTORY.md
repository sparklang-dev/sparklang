# Spark factory documentation (hub)

Engineer map for the **Spark / SparkLang** SPARK_BC factory on
[sparklang.dev](https://sparklang.dev/). Does **not** reimplement
SGD, attention, or serve APIs — links code + makefile targets.
**Never** claims beat Claude. **Never** trains on the RTX PRO 6000.

Reproduction story: [SPARK_BUILDER.md](SPARK_BUILDER.md).
**Diagrams:** [DIAGRAMS.md](DIAGRAMS.md) — tool map, shadows, LLM
assist vs deterministic SoT.

## Map (everything)

| Topic | Doc | Site |
|-------|-----|------|
| **Diagrams (tools + LLM)** | [DIAGRAMS.md](DIAGRAMS.md) | [/docs/diagrams.html](/docs/diagrams.html) |
| Compile / assemble | [COMPILE.md](COMPILE.md) | [/docs/compile.html](/docs/compile.html) |
| Decompile / dump / inspect | [DECOMPILE.md](DECOMPILE.md) | [/docs/decompile.html](/docs/decompile.html) |
| LLM decompile research | [research/LLM_DECOMPILE.md](research/LLM_DECOMPILE.md) | [/docs/llm-decompile.html](/docs/llm-decompile.html) |
| Opcode ISA (TRAIN/STEP/…) | [SPARK_BC.md](SPARK_BC.md) | [/docs/spark-bc.html](/docs/spark-bc.html) |
| Build models + weights | [BUILD_MODELS.md](BUILD_MODELS.md) | [/docs/build-models.html](/docs/build-models.html) |
| Train loop (outer/inner) | [TRAIN_LOOP.md](TRAIN_LOOP.md) | [/docs/train-loop.html](/docs/train-loop.html) |
| Architecture pieces | [ARCHITECTURE.md](ARCHITECTURE.md) | [/docs/architecture.html](/docs/architecture.html) |
| Attention / MLP honesty | [ATTENTION_FORWARD.md](ATTENTION_FORWARD.md) | [/docs/attention-forward.html](/docs/attention-forward.html) |
| Tokenizer / BPE | [TOKENIZER.md](TOKENIZER.md) | [/docs/tokenizer.html](/docs/tokenizer.html) |
| Serve forward + HTTP | [SERVE.md](SERVE.md) | [/docs/serve.html](/docs/serve.html) |
| Eval harness | [EVAL.md](EVAL.md) | [/docs/eval.html](/docs/eval.html) |
| Makefile targets | [SPARKBC_MAKE.md](SPARKBC_MAKE.md) | [/docs/sparkbc-make.html](/docs/sparkbc-make.html) |
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
| **D** | Attention train/serve math | Document as planned until on `main` |
| **E** | Claude eval harness | **Merged** — see [EVAL.md](EVAL.md) |
| **F** | Scale fixtures / dim knobs | **Merged** — see [TRAIN_LOOP.md](TRAIN_LOOP.md) / `spark-sgd-proof-scale` |
| **G** | Serve HTTP/API | **Merged** — see [SERVE.md](SERVE.md) / `make spark-serve-api` |
| **H** | Website + factory docs | **Merged** (#23) — this hub + [DIAGRAMS.md](DIAGRAMS.md) |
| **J** | Decompile research / captures | **Not merged yet** — when live, link from [DECOMPILE.md](DECOMPILE.md); flow diagrams stay in [DIAGRAMS.md](DIAGRAMS.md) |

## Honesty bar

- Multi-outer CPU SGD + MLP0 serve + frozen eval — **yes** on tip.
- Beat Claude — **no**.
- Full attention forward in serve — **no** (tensors allocated).
- 6000 train — **never**.
