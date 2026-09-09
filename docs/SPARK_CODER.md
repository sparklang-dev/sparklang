# Spark coder — owned TinyCoder (M-lane)

**Written and trained in this repo.** Not a HuggingFace / Claude /
OpenAI / Bifrost / vLLM wrapper. Prefers **RTX 5090** for GPU SGD
when available; CPU otherwise. **Never** the RTX PRO 6000. Does
**not** beat Claude.

## What it is

| Piece | Path |
|-------|------|
| Layers (embed, MLP, RMSNorm, lm_head) | `python/sparklang/spark_coder/layers.py` |
| Model + greedy generate | `python/sparklang/spark_coder/model.py` |
| CPU SGD train on coding JSONL | `python/sparklang/spark_coder/train.py` |
| Optional compile tool-loop | `python/sparklang/spark_coder/tools_loop.py` |
| CLI | `./spark-code` → `tools/spark-code/cli.py` |
| Coding fixtures (authored) | `examples/fixtures/coder/dataset.jsonl` |
| Packaged weights | `models/spark-coder/weights.safetensors` |

Seed weights come from Spark factory `emit_init_weights` on a
SPARK_BC program (`docs/examples/spark-train-step.sparkbc`). Training
is owned CE SGD (loss must drop) plus an optional factory
`apply_sgd_step` companion. The **brain** is those tensors — tools
only compile/verify.

## Quick start

```bash
make spark-bootstrap
make spark-coder-train          # writes models/spark-coder/
./spark-code status
./spark-code generate --prompt "Say exactly: spark" --max-new 8
./spark-code prove
make test-spark-coder
```

Tool loop (owned model ranks authored candidates, then compiles):

```bash
./spark-code tool-loop \
  --task "print hello spark" \
  --candidate examples/coder/print_hello.spark \
  --candidate examples/coder/train_step_slice.spark \
  --work out/spark-coder/tool-loop
```

## Honest capability

- Tiny byte-level LM (vocab 256, dim 32, last-token pool) —
  **useful for coding next-byte / short mnemonic tasks after
  overfit**, not a production assistant.
- Proves: loss drop, ≥50% accuracy on authored prove fixtures, and
  real `--compile` of fixture `.spark` programs.
- Does **not** claim beat Claude or full program synthesis from
  scratch at Claude quality.

## SDK pack

`make sdk-pack` includes `models/spark-coder/` (weights + arch +
checkpoint) and `bin/spark-code` when present after
`make spark-coder-train`.

## Related

- [BUILD_MODELS.md](BUILD_MODELS.md) · [TRAIN_LOOP.md](TRAIN_LOOP.md)
- [FACTORY.md](FACTORY.md) · [AI_MODELS.md](AI_MODELS.md)
