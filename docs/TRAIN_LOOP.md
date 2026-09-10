# Train loop — outer / inner SGD

How `STEP` applies **CPU** SGD on Spark safetensors. Spark /
SparkLang only. Implementation SoT:
`python/sparklang/model_lab/` + `tools/spark-bc-dump/apply_step.py`.
This page does not reimplement grads.

Opcodes / ARTIFACT: [BUILD_MODELS.md](BUILD_MODELS.md).
Dims / layers: [Architecture](ARCHITECTURE.md).

## Loop shape

| Knob | Default (tip) | Meaning |
|------|---------------|---------|
| `--outer` | `4` | Outer CE passes; each writes a `loss_curve` point |
| `--inner` | `8` | Inner micro-steps per outer |
| `--step` | `1` | STEP counter stamped into weights meta |
| Dataset | `examples/fixtures/train/dataset.jsonl` | JSONL pairs (tip scale) |

```bash
PYTHONPATH=python python3 tools/spark-bc-dump/apply_step.py \
 --sparkbc docs/examples/spark-train-step.sparkbc \
 --weights out/train/sgd-proof/weights.safetensors \
 --checkpoint out/train/sgd-proof/checkpoint.json \
 --dataset examples/fixtures/train/dataset.jsonl \
 --outer 4 --inner 8 --step 1
```

Or: `make spark-sgd-proof` (same path + eval).

## What is trained today

- Default (layer-0 attention): layer-0 last-query causal MHA CE on
 `q/k/v/o` (+ embed / `lm_head`) via `train_attn=True`.
- Fallback: `--no-train-attn` mean-pool embed → CE on `lm_head`.
- Optional: embed grads when the helper enables them.
- Device: **CPU** default; **RTX 5090 OK**. Never the voice GPU /
 6000.

## Checkpoint / loss curve

`checkpoint.json` (after a successful STEP) includes:

- `loss_before` / `loss_after` (after must be **lower** or fail loud)
- `loss_curve` — list of `{outer, loss, …}`
- `claim`: always **false**
- `device`: CPU

`ARTIFACT` under `out/train/<job>/` lists weights + checkpoint paths
and `not_sgd=false` / `trained=true` only when grads applied.

## Fixtures + scale

| Fixture | Role |
|---------|------|
| `examples/fixtures/train/dataset.jsonl` | STEP / sgd-proof pairs on tip |
| Larger multi-pair sets | Landed with multi-outer SGD; do not invent counts — read the file |
| Opt-in `dim` / `n_layer` + scale JSONL | **on tip** — `dataset_scale.jsonl`; `make spark-sgd-proof-scale`; CI keeps tiny `spark-sgd-proof` |
| Spark-coder tiny vs large | **tiny** CI (`make spark-coder-train`); **large** opt-in dim64/n_layer4 (`make spark-coder-train-large` / `./spark-code train --scale large`). Prefer **5090** SoT: `examples/fixtures/coder/scale_config.json` |

Do not claim FineWeb-scale data. Seed BPE corpus is separate:
[TOKENIZER.md](TOKENIZER.md). Larger Spark stubs still **measurement only**.

## SPARK_BC program path

1. `TRAIN` (`0x26`) — dry accept + `ARTIFACT` stub (`trained=false`)
2. `STEP` (`0x28`) — runs this loop
3. `TRAIN_STATUS` (`0x27`) — dry status JSON

Execute: `./spark-bootstrap --run-bc …` or `./spark --run-bc …`.

## Gates

```bash
make test-sparkbc # loss_after < loss_before among asserts
make sparkbc-e2e
make spark-sgd-proof
```

## Related

- [BUILD_MODELS.md](BUILD_MODELS.md) · [Eval](EVAL.md)
- [SPARKBC_MAKE.md](SPARKBC_MAKE.md) · [Factory hub](FACTORY.md)
