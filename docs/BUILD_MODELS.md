# Build models — TRAIN / STEP / ARTIFACT

How Spark **programs** training in SPARK_BC and what lands on disk.
Prefer CPU or a consumer GPU for train. (voice GPU). CPU fixtures only unless a future owner grant says
otherwise.

Full factory: [SPARK_BC Builder](SPARK_BUILDER.md). Language verbs:
[MODEL_TRAINING.md](MODEL_TRAINING.md) · [LANGUAGE.md](LANGUAGE.md).

## Opcodes in the binary

| Byte | Mnemonic | LANGUAGE | Disk / stdout |
|------|----------|----------|---------------|
| `0x26` | `TRAIN` | `model train` / `model build` | dry job JSON; writes `ARTIFACT` under `out/train/<job>/`; `trained=false` until STEP |
| `0x28` | `STEP` | `model step` | multi-outer **CPU SGD** → `weights.safetensors` + `checkpoint.json`; `trained=true` / `not_sgd=false` when grads apply |
| `0x27` | `TRAIN_STATUS` | `model status` | dry status JSON |

Dry fixture SoT: `bootstrap/dry_train.c`. Emitting TRAIN ≠ trained
weights.

## End-to-end (proof program)

Source: `examples/spark_train_step.spark` → published
`docs/examples/spark-train-step.sparkbc`.

```bash
./spark-bootstrap --compile examples/spark_train_step.spark \
 -o /tmp/spark-train-step.sparkbc
./spark-bootstrap --run-bc /tmp/spark-train-step.sparkbc
# → out/train/job-dry-001/ARTIFACT (+ weights after STEP)
```

Helper (same SGD as STEP path):

```bash
PYTHONPATH=python python3 tools/spark-bc-dump/apply_step.py \
 --sparkbc docs/examples/spark-train-step.sparkbc \
 --weights /tmp/weights.safetensors \
 --checkpoint /tmp/checkpoint.json \
 --dataset examples/fixtures/train/dataset.jsonl \
 --outer 4 --inner 8 --step 1
```

Implementation: `python/sparklang/model_lab/` (`apply_sgd_step`).
**Not** a second training SoT in docs — link the code.

## ARTIFACT / checkpoint status
- `ARTIFACT` — job marker text; after successful STEP lists
 weights + checkpoint paths and `not_sgd=false`.
- `weights.safetensors` — Spark tensors; meta `trained` must match
 reality (`false` for init-only, `true` after SGD).
- `checkpoint.json` — includes `loss_curve`, `loss_before` /
 `loss_after`, `claim: false`, `device` (CPU).

Gates fail loud if loss does not drop.

## Init vs STEP weights

| Artifact | Meaning |
|----------|---------|
| Init safetensors from `dump.py --weights` | Derived from SPARK_BC bytes; Xavier; **not** trained |
| STEP weights | Multi-outer CE on `lm_head` (+ optional embed); tiny fixture |

Init tensor layout (including **unused** attn Q/K/V/O slots):
`python/sparklang/model_lab/weights.py`. Serve path today uses
MLP0 only — [Attention / forward](ATTENTION_FORWARD.md).

## Makefile targets

```bash
make test-sparkbc # includes dump + SGD loss-drop asserts
make sparkbc-e2e # TRAIN→STEP→ARTIFACT (+ GAS --run-bc)
make spark-sgd-proof # SGD then measurement-only spark-eval
make spark-eval # frozen probes; exit 0 ≠ marketing win
make spark-eval WEIGHTS=out/train/sgd-proof/weights.safetensors
```

Details: [SPARKBC_MAKE.md](SPARKBC_MAKE.md).

## HTTP companion (live jobs)

`./spark-train-http` remains the live HTTP job path
([MODEL_TRAINING.md](MODEL_TRAINING.md)). `backend` on train lines
is parsed and skipped in SPARK_BC (not an operand).

## Honest bar

- Multi-outer CPU SGD on tiny Spark tensors — **yes** (tip
 `make spark-sgd-proof`).
- Production LLM / Competitive AI win claims — **no**.
- 6000 train — **never** from this lane.

## Related

- [Compile](COMPILE.md) · [Decompile](DECOMPILE.md)
- [Attention / forward](ATTENTION_FORWARD.md)
- [SPARK_BC Builder](SPARK_BUILDER.md) · [AI_MODELS.md](AI_MODELS.md)
