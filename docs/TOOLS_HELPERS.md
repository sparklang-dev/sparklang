# Tools & helpers (K-lane)

Ergonomic CLIs, shadow safety, and a small downloadable kit for the
Spark / SparkLang SPARK_BC factory. Does **not** reimplement attention
(D) or the serve HTTP API (G). **Never** 6000. Does **not** beat Claude.

Hub: [FACTORY.md](FACTORY.md). Make map: [SPARKBC_MAKE.md](SPARKBC_MAKE.md). Diagrams: [DIAGRAMS.md](DIAGRAMS.md).

## Quick invoke

```bash
make helpers          # chmod + list helpers
make tools-test       # unit/smoke for kit + shadows
make sdk-pack         # stage dist/spark-sdk/ (+ I overlay)
./helpers/spark-check-env
./helpers/spark-run examples/spark_builder.spark
./helpers/spark-bc-pp docs/examples/spark-train-step.sparkbc
./helpers/spark-bc-diff a.sparkbc b.sparkbc
./helpers/spark-train-proof          # make spark-sgd-proof
SCALE=1 ./helpers/spark-train-proof  # scale opt-in
./helpers/spark-shadow build-dir
./helpers/spark-shadow copy out/train/sgd-proof/weights.safetensors
./helpers/spark-shadow verify ORIG SHADOW
```

## Layout

| Path | Role |
|------|------|
| `helpers/` | one-shot compile/run/inspect, train proof, env check, BC pp/diff, shadow CLI |
| `shadows/` | docs for `build/shadow/` dual-path experiments |
| `tools/spark_kit/` | hexdump, opcode sheet, fixture lint, vocab inspect, bc_diff |
| `tools/spark_shadow/` | Python behind `spark-shadow` |
| `tools/package_helpers_k.sh` | `make sdk-pack` stager → `dist/spark-sdk/` |
| `dist/spark-sdk/` | downloadable helpers tree + `MANIFEST-helpers-k.json` |

## Tool kit CLIs

```bash
PYTHONPATH=python:tools python3 -m spark_kit.opcode_sheet
PYTHONPATH=python:tools python3 -m spark_kit.hexdump_bc \
  docs/examples/spark-train-step.sparkbc
PYTHONPATH=python:tools python3 -m spark_kit.fixture_lint \
  examples/fixtures/train/dataset.jsonl
PYTHONPATH=python:tools python3 -m spark_kit.vocab_inspect
PYTHONPATH=python:tools python3 -m spark_kit.bc_diff a.sparkbc b.sparkbc
```

## Sibling lanes

- **I** (SDK/IDE/GUI pack) — K is additive `helpers/` + `tools/spark_*`;
  `package_helpers_k.sh` overlays I’s `out/sdk-pack/stage/` when present.
- **H/J** — docs; this page is the Tools & helpers section to link.
- **D/G** — not touched here.

## Honesty

- Helpers wrap existing makefile / `spark-bootstrap` / `bc_dump` paths.
- Shadow verify compares SHA-256 (and optional recompile).
- Eval / train proofs remain measurement-only — **not** beat Claude.
