# Tools & helpers

Ergonomic CLIs, shadow safety, and a small downloadable kit for the
Spark / SparkLang SPARK_BC factory. Does **not** reimplement attention
train or the serve HTTP API — those live in their own docs.

Hub: [FACTORY.md](FACTORY.md). Make map: [SPARKBC_MAKE.md](SPARKBC_MAKE.md). Diagrams: [DIAGRAMS.md](DIAGRAMS.md).

## Quick invoke

```bash
make helpers          # chmod + list helpers
make tools-test       # unit/smoke for kit + shadows
make sdk-pack         # stage dist/spark-sdk/ (+ helpers overlay)
./helpers/spark-check-env
./helpers/spark-run examples/spark_builder.spark
./helpers/spark-analyze docs/examples/spark-train-step.sparkbc
./helpers/spark-analyze examples/spark_train_step.spark --ask
./helpers/spark-bc-pp docs/examples/spark-train-step.sparkbc
./helpers/spark-bc-diff a.sparkbc b.sparkbc
./helpers/spark-train-proof          # make spark-sgd-proof
SCALE=1 ./helpers/spark-train-proof  # scale opt-in
./helpers/spark-shadow build-dir
./helpers/spark-shadow copy out/train/sgd-proof/weights.safetensors
./helpers/spark-shadow verify ORIG SHADOW
./spark-ask docs/examples/spark-train-step.sparkbc \
  --text "What opcodes are in this dump?"
./spark-speak-ask docs/examples/spark-train-step.sparkbc --dry
```

Voice ask (STT→dump/TinyCoder→TTS): [VOICE_ASK.md](VOICE_ASK.md).
make test-spark-analyze
```

Project loop: `spark-analyze` writes a **local** folder
`out/analyze/<name>/` (dump, `ops.json`, REPORT stub, screenshot
placeholder; optional `--serve` / `--ask`). No upload. Methods note:
[METHODS_OPENBIN.md](METHODS_OPENBIN.md).

## Layout

| Path | Role |
|------|------|
| `helpers/` | one-shot compile/run/inspect, **analyze loop**, train proof, env check, BC pp/diff, shadow CLI |
| `tools/spark_analyze/` | Python behind `spark-analyze` |
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

## Related surfaces

- SDK/IDE/GUI pack — helpers are additive under `helpers/` +
  `tools/spark_*`; `package_helpers_k.sh` overlays the SDK pack
  stage when present.
- Diagrams / decompile docs — this page is the Tools & helpers
  section to link.
- Attention train / serve HTTP API — not touched here.

## Honesty

- Helpers wrap existing makefile / `spark-bootstrap` / `bc_dump` paths.
- Shadow verify compares SHA-256 (and optional recompile).
- Eval / train proofs remain measurement-only (see [EVAL.md](EVAL.md)).
