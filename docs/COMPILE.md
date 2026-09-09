# Compile — Spark → SPARK_BC / GAS / sparkasm

Engineer guide for **emitting** bytecode and related objects.
Product name: **Spark / SparkLang** only.

This page does **not** reimplement the compiler. It points at
makefile targets and in-tree tools. ISA detail:
[SPARK_BC.md](SPARK_BC.md). Factory story:
[SPARK_BUILDER.md](SPARK_BUILDER.md).
**Diagrams:** [DIAGRAMS.md](DIAGRAMS.md) (tools + LLM assist vs SoT).

## What “compile” means here

| Path | Input | Output | SoT |
|------|-------|--------|-----|
| **C bootstrap** | `.spark` | `.sparkbc` (`SPBC` magic) | `./spark-bootstrap --compile` |
| **GAS wrapper** | `.spark` | same `.sparkbc` | `./spark --compile` thin-forks bootstrap |
| **sparkasm** | `.sasm` / peer asm | ELF objects / tests | `make -C sparkasm` — **not** SPARK_BC |
| **Tensor asm check** | `control.sparkasm` | shape check only | `make test-sparkasm-control` — **not** a tensor VM |

SPARK_BC is an **orchestration ISA** (opcodes like `TRAIN` /
`STEP` / `HALT`). It is **not** neural weights, not CUDA, not a
HuggingFace export.

## Compile path diagram

![Compile path](/docs/images/diagram-compile-path.svg?v=0.6.58)

*Caption: `.spark` → bootstrap/GAS → `.sparkbc` → run/train/serve.
Full decompile diagrams + screenshots:
[DECOMPILE.md](DECOMPILE.md). LLM assist layout:
[research/LLM_DECOMPILE.md](research/LLM_DECOMPILE.md).*

## Bootstrap emit (SoT)

```bash
make spark-bootstrap   # or: make sparkc
./spark-bootstrap --compile examples/hello.spark -o /tmp/hello.sparkbc
./spark-bootstrap --compile examples/spark_train_step.spark \
  -o /tmp/spark-train-step.sparkbc
```

C lowering (`bootstrap/` + `selfhost/lex.c`) remains the encode
SoT. Published bytes live under `docs/examples/*.sparkbc` — rebuild
with the commands in [SPARK_BUILDER.md](SPARK_BUILDER.md); do not
invent hex.

## GAS `./spark --compile`

```bash
make spark
./spark --compile examples/spark_builder.spark \
  -o /tmp/spark-builder.sparkbc
```

Implemented as a **thin wrap** of `./spark-bootstrap` (exit status
propagates). GAS does **not** reimplement `.sparkbc` packing.

Source dry-run (not bytecode):

```bash
./spark --dry-run examples/hello.spark
```

## sparkasm (peer assembler)

```bash
make sparkasm
make test-sparkasm
```

Assembles Spark-asm IR → objects/binaries under `sparkasm/`.
**Separate** from SPARK_BC. See `sparkasm/README.md` and
[SELF_HOST.md](SELF_HOST.md).

Optional SPARK_BC → sasm emit probe (not the default factory
path):

```bash
make spark-bc-emit
make test-bc-emit
```

## Tensor-assembly source (control)

`examples/models/control.sparkasm` documents a tiny GQA + SwiGLU
forward **as macros**. It is **readable source + shape check**,
not a running attention VM:

```bash
make test-sparkasm-control
```

Honest status is in the file header and on
[Attention / forward](ATTENTION_FORWARD.md).

## Product wrapper

```bash
make spark-bc
./scripts/spark-bc   # phase-6 product wrapper; see scripts/spark-bc
```

Prefer `--compile` on bootstrap or GAS for engineer reproduction.

## Gates

| Target | What it proves |
|--------|----------------|
| `make test-sparkbc` | compile + `--run-bc` vs GAS dry oracle + dump tests |
| `make sparkbc-e2e` | TRAIN→STEP→ARTIFACT focused gate |
| `make test-bc-emit` | bc_emit + pack hello + sparkasm path |

Full target list: [SPARKBC_MAKE.md](SPARKBC_MAKE.md).

## Related

- [Decompile / dump](DECOMPILE.md)
- [Build models (TRAIN/STEP)](BUILD_MODELS.md)
- [SPARK_BC.md](SPARK_BC.md) · [SPARK_BUILDER.md](SPARK_BUILDER.md)
