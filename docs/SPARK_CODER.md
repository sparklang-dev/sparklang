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
| SGD train on coding JSONL | `python/sparklang/spark_coder/train.py` |
| Optional compile tool-loop | `python/sparklang/spark_coder/tools_loop.py` |
| CLI | `./spark-code` → `tools/spark-code/cli.py` |
| Coding fixtures (authored) | `examples/fixtures/coder/dataset.jsonl` |
| Scale SoT | `examples/fixtures/coder/scale_config.json` |
| Packaged weights (tiny) | `models/spark-coder/weights.safetensors` |
| Opt-in large pack | `models/spark-coder-large/` after train-large |

Seed weights come from Spark factory `emit_init_weights` on a
SPARK_BC program (`docs/examples/spark-train-step.sparkbc`). Training
is owned CE SGD (loss must drop) plus an optional factory
`apply_sgd_step` companion. The **brain** is those tensors — tools
only compile/verify.

## Tiny vs large (honesty)

| Scale | CI default? | dim | n_layer | Train | Device | VRAM note |
|-------|-------------|-----|---------|-------|--------|-----------|
| **tiny** | **yes** | 32 | 2 | `make spark-coder-train` · `./spark-code train --scale tiny` | CPU default; **5090 OK** | CPU-fast; 5090 busy heuristic if >28 GiB used |
| **large** | **no** (opt-in) | 64 | 4 | `make spark-coder-train-large` · `./spark-code train --scale large` | Prefer **5090**; CPU OK | Still tiny vs production LLMs; fits 5090 |

```bash
./spark-code scales   # JSON honesty table
```

SoT JSON: `examples/fixtures/coder/scale_config.json` (aligns with
F-lane `examples/fixtures/train/scale_config.json` dims).

**Hard refuse:** RTX PRO **6000** (voice-only). **Never** claim beat
Claude — larger dims ≠ Claude quality.

Voice / weight play paths use the **same** tiny|large + 5090 /
never-6000 rules (siblings own playground cores; this lane exposes
knobs + honesty).

## Quick start

```bash
make spark-bootstrap
make spark-coder-train          # tiny CI/default → models/spark-coder/
./spark-code status
./spark-code generate --prompt "Say exactly: spark" --max-new 8
./spark-code prove
make test-spark-coder
```

### Opt-in large (local; not GHA)

```bash
make spark-coder-train-large    # → models/spark-coder-large/
# or:
./spark-code train --scale large --device auto \
  --out models/spark-coder-large
```

Knobs: `SPARK_CODER_SCALE` (tiny train target), `SPARK_CODER_DEVICE`
(`auto`/`cpu`/`5090`), `SPARK_CODER_OUTER` / `INNER` / `LR` (large).

Tool loop (owned model ranks authored candidates, then compiles):

```bash
./spark-code tool-loop \
  --task "print hello spark" \
  --candidate examples/coder/print_hello.spark \
  --candidate examples/coder/train_step_slice.spark \
  --work out/spark-coder/tool-loop
```

## Honest capability

- Byte-level LM (vocab 256, last-token pool) — **useful for coding
  next-byte / short mnemonic tasks after overfit**, not a production
  assistant. Large is still a stub vs Claude / HF bases.
- Proves: loss drop, ≥50% accuracy on authored prove fixtures (tiny
  gate), and real `--compile` of fixture `.spark` programs.
- Does **not** claim beat Claude or full program synthesis from
  scratch at Claude quality.

## SDK pack

`make sdk-pack` includes `models/spark-coder/` (weights + arch +
checkpoint) and `bin/spark-code` when present after
`make spark-coder-train`. Large pack is opt-in local only.

## Related

- [BUILD_MODELS.md](BUILD_MODELS.md) · [TRAIN_LOOP.md](TRAIN_LOOP.md)
- [FACTORY.md](FACTORY.md) · [AI_MODELS.md](AI_MODELS.md)
- Factory scale: `make spark-sgd-proof-scale`
