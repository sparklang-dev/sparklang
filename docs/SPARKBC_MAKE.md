# SPARK_BC makefile targets

End-to-end gates and helpers for the Spark bytecode factory.
Copy-paste from the repo root after `make spark-bootstrap` /
`make spark` as needed. Spark / SparkLang only.

ISA: [SPARK_BC.md](SPARK_BC.md). Story:
[SPARK_BUILDER.md](SPARK_BUILDER.md).

## Core gates

| Target | Purpose |
|--------|---------|
| `make test-sparkbc` | `run_sparkbc.sh` + `tools/spark-bc-dump/test_dump.py` (compile, dump, serve, SGD asserts) |
| `make test-sparkbc-e2e` | Focused TRAIN→STEP→ARTIFACT (`tools/spark-bc-dump/run_e2e_gate.sh`) |
| `make sparkbc-e2e` | Alias for `test-sparkbc-e2e` |
| `make test-decompile-compete` | Richer dump symbols/xrefs + analysis project units |
| `make decompile-roundtrip` | compile→dump→recompile sha256 on published fixtures |
| `make decompile-bench` | SPARK_BC metrics + `website/data/decompile-scoreboard.json` |
| `make spark-sgd-proof` | Multi-outer CPU SGD → `checkpoint.json` loss drop → `make spark-eval WEIGHTS=…` |
| `make spark-sgd-proof-scale` | Local opt-in larger JSONL + dim/n_layer (scale fixtures; not default CI) |
| `make spark-coder-train` | Owned TinyCoder **tiny** (CI/default); prefer 5090 |
| `make spark-coder-train-large` | Opt-in **large** coder (dim 64 / n_layer 4); not GHA default |
| `make weight-gallery` | Catalog + emit scale/large samples + website catalog JSON |
| `make test-weights-play` | Weight gallery unit + CLI play/diff/stats |
| `make weight-gallery-xl` | Opt-in XL emit (prefer 5090) |
| `make spark-eval` | Frozen copy/recall + next-token probes; exit 0 = harness ran (**not** beat Claude) |
| `make spark-eval-claude` | Same + optional Anthropic baseline (skip if no key) |
| `make test-spark-eval` | Unit gate for eval harness |
| `make docs-html` / `make docs-check` | Regen `website/docs/*` + nav link check |
| `make spark-serve-api` / `make test-serve-api` | serve API path HTTP/stdio predict + embeddings |
| `make helpers` / `make tools-test` | Helper CLIs + kit/shadow/analyze smoke |
| `make test-spark-ask` | Voice/text ask loop (dump facts + dry TTS) |
| `make test-spark-analyze` | Project-loop analyze folder gate |
| `make sdk-pack` / `make dist` | Stage `dist/spark-sdk/` (helpers overlay when present) |
| `make voice-easy` / `make test-voice-easy` | Owned voice STT/TTS heads — tiny dry (CI) |
| `make voice-easy-large` | Opt-in large voice-easy (prefer 5090; not default CI) |

```bash
make test-sparkbc
make sparkbc-e2e
make spark-sgd-proof
make spark-eval
make spark-eval-claude
make docs-check
make tools-test
make sdk-pack
make test-voice-easy
```

## Build / tools

| Target | Purpose |
|--------|---------|
| `make spark-bootstrap` / `make sparkc` | C bootstrap VM + `--compile` / `--run-bc` |
| `make spark` | GAS ELF (`./spark`) |
| `make spark-serve` | Install `./spark-serve` companion script |
| `make spark-bc` | Product wrapper script (`scripts/spark-bc`) |
| `make spark-bc-emit` / `make test-bc-emit` | SPARK_BC → sasm emit probe + pack hello |
| `make sparkasm` / `make test-sparkasm` | Peer assembler |
| `make test-sparkasm-control` | `control.sparkasm` shape check |
| `make test-model-lab` | `examples/model_lab.spark` dry + expects |
| `make test-bootstrap` | Bootstrap VM suite |
| `make test-bpe-seed` | Tokenizer BPE seed (when present) |

## Helpers / shadows

See [TOOLS_HELPERS.md](TOOLS_HELPERS.md).

| Path | Role |
|------|------|
| `helpers/spark-run` | compile → run-bc → dump |
| `helpers/spark-analyze` | project loop → `out/analyze/<name>/` (optional `--serve`/`--ask`) |
| `helpers/spark-train-proof` | wrap `spark-sgd-proof` (`SCALE=1` → scale) |
| `helpers/spark-check-env` | env / fixture / import check |
| `helpers/spark-bc-pp` / `spark-bc-diff` | pretty-print / diff `.sparkbc` |
| `helpers/spark-shadow` | shadow copy, `build/shadow/`, hash verify |
| `./spark-ask` / `./spark-speak-ask` | voice/text ask over dump / analysis dir |
| `tools/spark_kit/` | hexdump, opcode sheet, fixture lint, vocab inspect |

## Docs / site regen

```bash
make docs-html
make docs-check
# Mirror CHANGELOG.md → website/CHANGELOG.html for Pages when cutting
```

Release + Pages: [CI_PAGES.md](CI_PAGES.md) · [RELEASE.md](RELEASE.md).

## Scripts (not always phony targets)

| Path | Role |
|------|------|
| `scripts/sparkbc-e2e` | Wrapper around e2e gate |
| `scripts/spark-bc` | Phase-6 compile→bc_vm product wrapper |
| `bootstrap/tests/run_sparkbc.sh` | Oracle compare for `test-sparkbc` |
| `tools/spark-bc-dump/apply_step.py` | CPU SGD helper used by `spark-sgd-proof` |
| `tools/spark-eval/run.py` | Eval harness |
| `tools/package_helpers_k.sh` | `dist/spark-sdk/` helpers stager |

## CI

GitHub Actions workflow `.github/workflows/sparkbc.yml` runs the
SPARK_BC gates on PRs (includes `make tools-test` + `make sdk-pack`).
Prefer green `test-sparkbc` + `sparkbc-e2e` before claiming factory
docs match tip.

## Never

- Claim `spark-eval` scores beat Claude.
- Raise train onto the RTX PRO 6000 from these targets.
- Treat empty / failing gates as soft success.

## Related

- [FACTORY.md](FACTORY.md) · [COMPILE.md](COMPILE.md) · [EVAL.md](EVAL.md)
- [CI_PAGES.md](CI_PAGES.md) · [TRAIN_LOOP.md](TRAIN_LOOP.md)
- [TOOLS_HELPERS.md](TOOLS_HELPERS.md)
