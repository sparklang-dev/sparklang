# Decompile / inspect / disassemble

How to **read** SPARK_BC and related binaries. Spark / SparkLang
only. No invented hex — dump tools read real files from `--compile`.

## SPARK_BC hex + mnemonic dump (primary)

```bash
PYTHONPATH=python python3 tools/spark-bc-dump/dump.py \
  docs/examples/spark-train-step.sparkbc \
  --source examples/spark_train_step.spark \
  --command './spark-bootstrap --compile examples/spark_train_step.spark -o docs/examples/spark-train-step.sparkbc' \
  -o /tmp/spark-train-step-bc.txt
```

- Loader / formatters: `python/sparklang/model_lab/bc_dump.py`
- CLI: `tools/spark-bc-dump/dump.py`
- Unit coverage: `tools/spark-bc-dump/test_dump.py` (via
  `make test-sparkbc`)

Published dump text (for strangers without a rebuild):
`docs/examples/*-bc.txt`. Site mirrors under
`website/docs/examples/` when synced.

### Stub JSON (builder metadata)

```bash
PYTHONPATH=python python3 tools/spark-bc-dump/dump.py \
  docs/examples/spark-builder.sparkbc --stub -o /tmp/stub.json
```

### Init weights from bytecode (not trained)

```bash
PYTHONPATH=python python3 tools/spark-bc-dump/dump.py \
  docs/examples/spark-self.sparkbc \
  --weights /tmp/spark-self.init.safetensors
```

Emits Spark-created Xavier init (`trained: false`). See
[BUILD_MODELS.md](BUILD_MODELS.md).

## Run bytecode (inspect behavior)

```bash
./spark-bootstrap --run-bc docs/examples/spark-train-step.sparkbc
./spark --run-bc docs/examples/spark-train-step.sparkbc   # GAS → bc_vm
```

Dry stdout contracts are in [SPARK_BC.md](SPARK_BC.md). TRAIN /
STEP JSON lines + `ARTIFACT` under `out/train/<job>/`.

## Model lab reverse / inspect

GAS-first (no SPARK_BC opcode yet):

```bash
./spark --dry-run examples/model_lab.spark
make test-model-lab
```

`model reverse` / `inspect` read local `config.json` + safetensors
**index names** only — no tensor body theft. Runbook:
[MODEL_LAB.md](MODEL_LAB.md).

## ELF / machine disassembly (not SPARK_BC)

For native companions / machine-proof paths (programming guide):

```bash
make machine-proof   # ELF64 + _start disassembly when binary exists
```

Language surface `binary` / decompile artifacts may land under
`out/decompile/<basename>/` (`ALL_SECTIONS.disasm`, etc.) — that
path is **ELF section dump**, not SPARK_BC decode. Do not confuse
with `tools/spark-bc-dump`.

## sparkasm objects

```bash
make -C sparkasm test
```

Disassemble assembled objects with host `objdump` if needed; there
is no Spark-branded SPARK_BC↔ELF round-trip claim beyond
`test-bc-emit`.

## What is not “decompile”

| Claim | Status |
|-------|--------|
| Hex + opcode mnemonics for `.sparkbc` | **implemented** (`dump.py`) |
| Recover original `.spark` source losslessly | **not** — dump is inspect, not a source decompiler |
| Attention head activation maps | **not** — serve skips attn; see [ATTENTION_FORWARD.md](ATTENTION_FORWARD.md) |
| Closed-weight model theft | **forbidden** — reverse stays index-only |

## Related

- [Compile](COMPILE.md) · [Build models](BUILD_MODELS.md)
- [SPARK_BUILDER.md](SPARK_BUILDER.md) · [SPARK_BC.md](SPARK_BC.md)
