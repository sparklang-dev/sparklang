# Spark coder — owned TinyCoder (spark-coder)

**Written and trained in this repo.** Not a HuggingFace / Claude /
OpenAI / the AI gateway / vLLM wrapper. Prefers **RTX 5090** for GPU SGD
when available; CPU otherwise.

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

## Tiny vs large
| Scale | CI default? | dim | n_layer | Train | Device | VRAM note |
|-------|-------------|-----|---------|-------|--------|-----------|
| **tiny** | **yes** | 32 | 2 | `make spark-coder-train` · `./spark-code train --scale tiny` | CPU default; **5090 OK** | CPU-fast; 5090 busy heuristic if >28 GiB used |
| **large** | **no** (opt-in) | 64 | 4 | `make spark-coder-train-large` · `./spark-code train --scale large` | Prefer **5090**; CPU OK | Still tiny vs production LLMs; fits 5090 |

```bash
./spark-code scales # JSON scale table
```

SoT JSON: `examples/fixtures/coder/scale_config.json` (aligns with
scale fixtures `examples/fixtures/train/scale_config.json` dims).

**Hard refuse:** reserved voice GPUs for factory train. Larger dims are still
fixture-scale — **measurement only**, not a marketing win.

Voice / weight play paths use the **same** tiny|large + 5090 /
consumer-GPU train rules (siblings own playground cores; this path exposes
knobs + scale table).

## Quick start

```bash
make spark-bootstrap
make spark-coder-train # tiny CI/default → models/spark-coder/
./spark-code status
./spark-code generate --prompt "Say exactly: spark" --max-new 8
./spark-code prove
make test-spark-coder
```

### Opt-in large (local; not GHA)

```bash
make spark-coder-train-large # → models/spark-coder-large/
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
- or full program synthesis from
 scratch at Claude quality.

## SDK pack

`make sdk-pack` includes `models/spark-coder/` (weights + arch +
checkpoint) and `bin/spark-code` when present after
`make spark-coder-train`. Large pack is opt-in local only.

## Grounding / anti-guess

TinyCoder still **guesses** next bytes. For grounded Q&A that must
not invent facts, wrap answers with `./spark-ground` (expect /
fixture / dump / schema) or language `expect` + abstain heads.
External Qwen-class adapt stays attach-only via
`model modify` / `spark-ground adapter-attach`; full SFT is opt-in
on a consumer GPU — not on reserved voice GPUs.

Docs: [knowledge/SAFETY_LIMITS.md](knowledge/SAFETY_LIMITS.md).

## Related

- [BUILD_MODELS.md](BUILD_MODELS.md) · [Train loop](TRAIN_LOOP.md)
- [Factory hub](FACTORY.md) · [AI_MODELS.md](AI_MODELS.md)
- [knowledge/SAFETY_LIMITS.md](knowledge/SAFETY_LIMITS.md)
- Factory scale: `make spark-sgd-proof-scale`
