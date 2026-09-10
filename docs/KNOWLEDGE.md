# AI knowledge hive

Engineer-grade **AI concepts** framed for **Spark / SparkLang** —
transformers, training, inference, multimodal, agents, evaluation,
and decompile limits. Original diagrams (not scraped paper figures).
Citations point at primary papers and surveys.

**Never** publishes competitive AI win claims. Spark factory train prefers CPU / RTX 5090 (see [Factory hub](FACTORY.md) GPU policy). Not an OpenBin clone.

Topics below follow the same **category → subcategory** map as the
Hive nav: Foundations · Systems · Safety / Eval · RE.

## Foundations

| Topic | Page | What you get |
|-------|------|--------------|
| LLMs & transformers | [knowledge/LLM_TRANSFORMERS.md](knowledge/LLM_TRANSFORMERS.md) | Tokens → embed → attention → MLP; embeddings |
| Training stack | [knowledge/TRAINING.md](knowledge/TRAINING.md) | Pretrain, SFT, RLHF/RLAIF, LoRA/QLoRA, SGD/Adam |
| Inference | [knowledge/INFERENCE.md](knowledge/INFERENCE.md) | Sampling, KV cache, quantization |

## Systems

| Topic | Page | What you get |
|-------|------|--------------|
| Multimodal | [knowledge/MULTIMODAL.md](knowledge/MULTIMODAL.md) | STT / TTS / vision |
| Agents & tools | [knowledge/AGENTS_TOOLS.md](knowledge/AGENTS_TOOLS.md) | Tool loops, ReAct-style patterns |

## Safety / Eval

| Topic | Page | What you get |
|-------|------|--------------|
| Evaluation | [knowledge/EVAL_STATUS.md](knowledge/EVAL_STATUS.md) | Benchmarks, baselines, frozen probes |
| Safety & limits | [knowledge/SAFETY_LIMITS.md](knowledge/SAFETY_LIMITS.md) | Model limits → Guardrails → Grounding (`./spark-ground`) |

## RE

| Topic | Page | What you get |
|-------|------|--------------|
| Decompile + LLM RE | [knowledge/DECOMPILE_RE.md](knowledge/DECOMPILE_RE.md) | Link to existing research; recompile ≠ semantics |
| LLM decompile research | [research/LLM_DECOMPILE.md](research/LLM_DECOMPILE.md) | Factory research page |

## Spark cross-links (factory SoT)

| Surface | Doc |
|---------|-----|
| Factory hub | [Factory hub](FACTORY.md) |
| Workflow loop | [/workflow.html](/workflow.html) |
| Voice / STT / TTS | [VOICE.md](VOICE.md) |
| Model aspects | [Model aspects](MODEL_ASPECTS.md) |
| Spark coder | [Spark coder](SPARK_CODER.md) |
| Train loop | [Train loop](TRAIN_LOOP.md) |
| Tokenizer / BPE | [TOKENIZER.md](TOKENIZER.md) |
| Attention / forward | [Attention / forward](ATTENTION_FORWARD.md) |
| Eval harness | [Eval](EVAL.md) |
| LLM decompile research | [research/LLM_DECOMPILE.md](research/LLM_DECOMPILE.md) |
| Tutorials | [/learn/](/learn/) |

## How to read this hive

1. Start with **Foundations → LLMs & transformers** for the math sketch.
2. Jump to **Training** / **Inference** for practice vocabulary.
3. Use **RE** before trusting pretty recovered C.
4. Prefer Spark factory docs for *what ships*; this hive explains *the field*.

```mermaid
flowchart LR
 H[Knowledge hive] --> F[Foundations]
 H --> S[Systems]
 H --> SE[Safety / Eval]
 H --> R[RE]
 F --> T[Transformers]
 F --> TR[Training]
 F --> I[Inference]
 S --> M[Multimodal]
 S --> A[Agents]
 SE --> E[Evaluation]
 SE --> Saf[Safety]
 R --> D[Decompile RE]
 D --> L[llm-decompile.html]
 TR --> Fac[factory / spark-coder]
```
