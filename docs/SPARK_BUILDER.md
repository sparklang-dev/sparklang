# Builder — SPARK_BC factory

Spark compiles Spark to **SPARK_BC**. The same factory emits:

1. **Orchestration + training program** — opcodes in the `.sparkbc`
   (including `TRAIN` / `STEP` / `TRAIN_STATUS`)
2. **Init weights** — Spark-created safetensors derived from those
   bytes

The seed is our instruction binary, not an imported checkpoint.

**ISA:** [SPARK_BC.md](SPARK_BC.md). Bytecode is not neural weights
and not a second tensor ISA.

Honest today: **init / Spark-created**. Not trained. Not served.
Emitting a train segment ≠ a trained model. Later train (owner
grant, not the 6000) aims to beat **Claude**. Do not import Claude
or Grok weights.

## Pipeline (implemented)

1. Compiler seed: `selfhost/compile.spark`. Train slice seed:
   `selfhost/compile_train.spark`. Builder program (includes
   `model train` / `model status`): `examples/spark_builder.spark`.
   Loop tick (`model step`): `examples/spark_train_step.spark`
   → TRAIN → STEP → TRAIN_STATUS in one stream.
2. Compile → real SPARK_BC, including train ops:

```bash
./spark-bootstrap --compile examples/spark_builder.spark \
  -o docs/examples/spark-builder.sparkbc
```

Compiler-seed slice (MODEL / ASK / PRINT / HALT only):

```bash
./spark-bootstrap --compile selfhost/compile.spark \
  -o docs/examples/spark-self.sparkbc
```

Selfhost seed **with** train ops (`TRAIN` / `TRAIN_STATUS`):

```bash
./spark-bootstrap --compile selfhost/compile_train.spark \
  -o docs/examples/spark-selfhost-train.sparkbc
```

3. Dump hex + decode, then emit weights from **those** bytes:

```bash
PYTHONPATH=python python3 tools/spark-bc-dump/dump.py \
  docs/examples/spark-builder.sparkbc \
  --source examples/spark_builder.spark \
  --command './spark-bootstrap --compile examples/spark_builder.spark -o docs/examples/spark-builder.sparkbc' \
  --label 'Builder SPARK_BC (train ops in the binary)' \
  -o docs/examples/spark-builder-bc.txt

PYTHONPATH=python python3 tools/spark-bc-dump/dump.py \
  docs/examples/spark-self.sparkbc \
  --source selfhost/compile.spark \
  --command './spark-bootstrap --compile selfhost/compile.spark -o docs/examples/spark-self.sparkbc' \
  --weights docs/examples/spark-self.init.safetensors \
  -o docs/examples/spark-self-builder.json
```

`asm/spark.s` is the GAS VM (ELF). `./spark --dry-run` **executes**
train verbs from `.spark` source. GAS does **not emit** `.sparkbc`
(**BLOCKED** — use bootstrap `--compile`).

## Bytecode dump

Published: [spark-builder-bc.txt](examples/spark-builder-bc.txt)
(TRAIN in the stream),
[spark-self-bc.txt](examples/spark-self-bc.txt) (compiler seed),
and [spark-selfhost-train.sparkbc](examples/spark-selfhost-train.sparkbc)
(`selfhost/compile_train.spark`).

- Magic `SPBC`, version 1, string pool, const pool, opcode stream
- Hex from `xxd` of the compiled file — not invented
- Builder ops: `MODEL` `ASK` `PRINT` `TRAIN` `TRAIN_STATUS` `HALT`
- `TRAIN` is opcode **`0x26`**. `TRAIN_STATUS` is **`0x27`**.
  Loop tick `STEP` is **`0x28`** (see
  [spark-train-step.sparkbc](examples/spark-train-step.sparkbc)).

```bash
./spark --dry-run examples/spark_builder.spark
./spark-bootstrap --run-bc docs/examples/spark-builder.sparkbc
```

`./spark-bootstrap --run-bc` **executes** `TRAIN` (`0x26`) then
`TRAIN_STATUS` (`0x27`) from that file: dry JSON plus an `ARTIFACT`
marker under `out/train/<job>/`. That is a **dry fixture**
(`trained=false`), not SGD and not a trained model.

GAS `./spark` has **no SPARK_BC emit path** and **no** `--run-bc`.
Proof (must fail):

```bash
./spark --run-bc docs/examples/spark-builder.sparkbc
# exits 1: need --dry-run|--live <file.spark>
```

GAS still runs `model train` from **`.spark` source**
(`./spark --dry-run examples/spark_builder.spark`). That is not
bytecode execution and does not write a `.sparkbc`.

`model_lab.spark` lab verbs (`reverse` / `compile` / `modify`) stay
**GAS-first** — no SPARK_BC opcode yet. C `--compile` of that file
fails loud. Train **does** run from SPARK_BC on bootstrap.

## Weights

`docs/examples/spark-self.init.safetensors` — **Spark-created init**.

- Named control-model tensors: `embed`, per-layer `q/k/v/o`,
  `mlp_up/gate/down`, RMS-style `*.norm.weight`, `lm_head`
- Shapes from SPARK_BC (`ncode`, string count) — small on purpose
- Xavier / fan-in scale
- Embed rows mix in the real bytecode (magic, opcodes, strings)
- Written by our safetensors packer — no HuggingFace load
- **No imported weights** — not Claude, Grok, or a hub checkpoint

**trained: false.** Not a foundation model. The training **program**
is in the `.sparkbc`; the tensors are still init.

## Status

| Claim | Today |
|-------|--------|
| Compile Spark → SPARK_BC | **implemented** (`--compile`) |
| Train / status ops in the binary | **implemented** (`0x26` / `0x27`) |
| Selfhost train seed `.sparkbc` | **implemented** (`compile_train.spark` → `spark-selfhost-train.sparkbc`) |
| Execute TRAIN from published `.sparkbc` | **implemented** (`./spark-bootstrap --run-bc`; dry; `trained=false`) |
| GAS `./spark --dry-run` train verbs | **implemented** (source, not bytecode) |
| GAS emit `.sparkbc` / `--run-bc` | **BLOCKED** (use bootstrap `--compile` / `--run-bc`) |
| Dry ARTIFACT from TRAIN | **implemented** (fixture; not SGD) |
| Hex dump + decode | **implemented** |
| Emit init weights from those bytes | **implemented** (init only) |
| Round-trip hello SPARK_BC | **tested against oracle** (`make test-sparkbc`) |
| Trained / served / beats Claude | **not** |

## Related

- [SPARK_BC.md](SPARK_BC.md)
- [MODEL_LAB.md](MODEL_LAB.md)
- [AI_MODELS.md](AI_MODELS.md)
- [LANGUAGE.md](LANGUAGE.md)
- [SELF_HOST.md](SELF_HOST.md)
- [MODEL_TRAINING.md](MODEL_TRAINING.md)
