# Builder — SPARK_BC factory

Engineer reproduction guide. A stranger with this repo and a built
`./spark-bootstrap` + `./spark` can re-create every published artifact
from the commands below. Do not invent hashes — cite `sha256sum` of
files under `docs/examples/`.

## What Spark emits (two different things)

| Artifact | What it is | What it is **not** |
|----------|------------|---------------------|
| **SPARK_BC** (`.sparkbc`) | Orchestration **ISA** — packed magic `SPBC`, string/const pools, opcode stream (`MODEL` / `ASK` / `PRINT` / `TRAIN` / `STEP` / `TRAIN_STATUS` / `HALT`, …) | Neural weights, a tensor ISA, HuggingFace, CUDA kernels |
| **Init safetensors** | Spark-created tensors **derived from** those bytecode bytes (Xavier / fan-in; embed rows mix in magic + opcodes + strings) | A Claude-beating checkpoint, an imported hub weight dump |
| **STEP weights** | Multi-outer **CPU SGD** on Spark `lm_head`(+embed) from fixture JSONL (`trained=true`, `not_sgd=false`, `checkpoint.json` loss curve) | A production LLM; beating Claude |

Bytecode is the **training program + orchestration**. Init tensors stay
`trained: false` until `STEP` runs. Emitting `TRAIN` alone ≠ trained.
`STEP` now applies **multi-outer CPU SGD** on tiny Spark tensors
(larger fixture; loss curve in `checkpoint.json`; loss must drop or
fail loud). **Does not beat Claude.** No 6000 / GPU-1 train. Do not
import Claude or Grok weights.

**ISA SoT:** [SPARK_BC.md](SPARK_BC.md).

## Factory story (end-to-end)

1. **Seed programs** — compiler slice, train slice, builder, STEP proof,
   optional model lab (see [Programs](#programs)).
2. **`--compile`** — `./spark-bootstrap --compile … -o ….sparkbc`
   **or** `./spark --compile … -o ….sparkbc` (GAS thin fork).
   C lowering remains SoT; that is the factory emit path.
3. **Opcodes in the binary** — `TRAIN` `0x26`, `TRAIN_STATUS` `0x27`,
   `STEP` `0x28` (plus `MODEL` / `ASK` / `PRINT` / `HALT` as needed).
4. **`--run-bc`** — `./spark-bootstrap --run-bc ….sparkbc` **or**
   `./spark --run-bc ….sparkbc` (GAS thin fork → bootstrap bc_vm)
   runs `TRAIN` as a dry job accept (`trained=false` until STEP),
   then **`STEP` as multi-outer CPU SGD** on Spark safetensors
   (`ARTIFACT` + `weights.safetensors` + `checkpoint.json`;
   `trained=true` / `not_sgd=false` only after real grads; loss must
   drop). Helper: `tools/spark-bc-dump/apply_step.py` →
   `apply_sgd_step` (outer×inner CE; optional embed grads).
   **Not beat Claude.** No 6000.
5. **GAS dry-run + wrappers** — `./spark --dry-run file.spark` runs
   train verbs from **source**. `./spark --run-bc` and
   `./spark --compile … -o …` thin-wrap bootstrap (bc_vm / C
   lowering remain SoT).
6. **Dump + init weights** — hex/mnemonic dump of the real file; emit
   `spark-self.init.safetensors` from those bytes (no HF load).
7. **Later beat Claude** — larger train / eval path. **Not this STEP.**

**Learn trail:** [/learn/](/learn/) →
[Build a Model](/learn/build-model.html) →
[/docs/spark-builder.html](/docs/spark-builder.html).
**Diagrams:** [/docs/diagrams.html](/docs/diagrams.html) (tools,
shadows, LLM assist vs SoT).

## Opcodes (train family)

From [SPARK_BC.md](SPARK_BC.md) / [LANGUAGE.md](LANGUAGE.md). Operands
are `u16` little-endian constant-pool indices.

| Byte | Mnemonic | LANGUAGE form | Operands | Behavior |
|------|----------|---------------|----------|----------|
| `0x26` | `TRAIN` | `model train` / `model build` | dataset, base, out, method, bind | `[model] {dry train JSON}`; writes `ARTIFACT` under `out/train/<job>/`; `trained=false` until STEP |
| `0x27` | `TRAIN_STATUS` | `model status` | job_id, bind | `[model] {dry status JSON}` |
| `0x28` | `STEP` | `model step "job-id" -> bind` | job_id, bind | `[model] {cpu-sgd step JSON}`; CPU SGD → `ARTIFACT` + `weights.safetensors` (`trained=true`, `not_sgd=false`) |

`backend` is parsed and skipped (HTTP companion); not a BC operand.
Dry fixture implementation: `bootstrap/dry_train.c`. Execute with
`./spark-bootstrap --run-bc` or `./spark --run-bc` (GAS → bootstrap).
Emit: `./spark-bootstrap --compile` or `./spark --compile`.

## Programs

| Source | Role | Published `.sparkbc` |
|--------|------|----------------------|
| `selfhost/compile.spark` | Compiler seed (MODEL / ASK / PRINT / HALT) | `docs/examples/spark-self.sparkbc` |
| `selfhost/compile_train.spark` | Selfhost train seed (`TRAIN` + `TRAIN_STATUS`) | `docs/examples/spark-selfhost-train.sparkbc` |
| `examples/spark_builder.spark` | Builder program (`train` + `status`) | `docs/examples/spark-builder.sparkbc` |
| `examples/spark_train_step.spark` | STEP proof (`TRAIN` → `STEP` → `TRAIN_STATUS`) | `docs/examples/spark-train-step.sparkbc` |
| `examples/model_lab.spark` | Lab: reverse / compile / train / modify + abstain (GAS-first for reverse/compile/modify) | *(no published lab `.sparkbc` — C `--compile` of lab verbs fails loud; use `make test-model-lab`)* |

## Reproduce from a clean tree

Requires: `make` (or at least `spark-bootstrap` + `spark`), Python 3 for
the dump tool.

### 1) Compile → published paths

```bash
./spark-bootstrap --compile examples/spark_builder.spark \
  -o docs/examples/spark-builder.sparkbc

./spark-bootstrap --compile selfhost/compile.spark \
  -o docs/examples/spark-self.sparkbc

./spark-bootstrap --compile selfhost/compile_train.spark \
  -o docs/examples/spark-selfhost-train.sparkbc

./spark-bootstrap --compile examples/spark_train_step.spark \
  -o docs/examples/spark-train-step.sparkbc
```

Verify bytes match the published hashes (see [Published files](#published-files--sha256)):

```bash
sha256sum docs/examples/spark-*.sparkbc
```

### 2) Dump hex + decode (+ init weights from compiler seed)

```bash
PYTHONPATH=python python3 tools/spark-bc-dump/dump.py \
  docs/examples/spark-builder.sparkbc \
  --source examples/spark_builder.spark \
  --command './spark-bootstrap --compile examples/spark_builder.spark -o docs/examples/spark-builder.sparkbc' \
  --label 'Builder SPARK_BC (train ops in the binary)' \
  -o docs/examples/spark-builder-bc.txt

PYTHONPATH=python python3 tools/spark-bc-dump/dump.py \
  docs/examples/spark-train-step.sparkbc \
  --source examples/spark_train_step.spark \
  --command './spark-bootstrap --compile examples/spark_train_step.spark -o docs/examples/spark-train-step.sparkbc' \
  --label 'Train-step SPARK_BC (TRAIN → STEP → TRAIN_STATUS)' \
  -o docs/examples/spark-train-step-bc.txt

PYTHONPATH=python python3 tools/spark-bc-dump/dump.py \
  docs/examples/spark-self.sparkbc \
  --source selfhost/compile.spark \
  --command './spark-bootstrap --compile selfhost/compile.spark -o docs/examples/spark-self.sparkbc' \
  --weights docs/examples/spark-self.init.safetensors \
  -o docs/examples/spark-self-builder.json
```

Site mirrors of dumps live under `website/docs/examples/`. Copy
txt/json dumps there when regenerating the site; do not invent hex.

### 3) Execute bytecode (TRAIN dry + STEP CPU SGD)

```bash
./spark-bootstrap --run-bc docs/examples/spark-builder.sparkbc
./spark-bootstrap --run-bc docs/examples/spark-train-step.sparkbc
# Same path via GAS (forks spark-bootstrap bc_vm):
./spark --run-bc docs/examples/spark-builder.sparkbc
./spark --run-bc docs/examples/spark-train-step.sparkbc
# TRAIN accept is still a dry job marker; STEP runs CPU SGD.
# trained=true / not_sgd=false only after apply_sgd_step grads.
# tools/spark-bc-dump/apply_step.py → apply_sgd_step
# (multi-outer CE + checkpoint.json; not hash toy).
ls -la out/train/job-dry-001/ARTIFACT \
  out/train/job-dry-001/weights.safetensors \
  out/train/job-dry-001/checkpoint.json

# Proof STEP SGD (clean job dir first):
rm -f out/train/job-dry-001/{ARTIFACT,weights.safetensors,checkpoint.json}
./spark --run-bc docs/examples/spark-train-step.sparkbc
# → weights.safetensors (step_n>=1, loss_after < loss_before)
# → checkpoint.json (loss_curve; beats_claude=false)
```

### 4) GAS source dry-run (not bytecode emit)

```bash
./spark --dry-run examples/spark_builder.spark
./spark --dry-run examples/spark_train_step.spark
./spark --dry-run examples/model_lab.spark
```

### 5) GAS wrappers (same SoT as bootstrap)

```bash
./spark --compile examples/spark_builder.spark \
  -o /tmp/builder.sparkbc
# thin-wrap → ./spark-bootstrap --compile (bytes match published)

./spark --run-bc docs/examples/spark-builder.sparkbc
# thin-wrap → ./spark-bootstrap --run-bc (dry fixture)
```

### 6) Automated gates already on main

```bash
make test-sparkbc      # compile → --run-bc body vs GAS dry (oracle)
make test-model-lab    # examples/model_lab.spark dry + expects
make sparkbc-e2e       # TRAIN→STEP→ARTIFACT focused gate
# alias: make test-sparkbc-e2e
```

### 6b) Tiny CPU serve forward (not production LLM)

```bash
PYTHONPATH=python python3 tools/spark-bc-dump/dump.py \
  docs/examples/spark-builder.sparkbc \
  --source examples/spark_builder.spark \
  --command './spark-bootstrap --compile examples/spark_builder.spark -o docs/examples/spark-builder.sparkbc' \
  --serve /tmp/serve-dry-001
# → /tmp/serve-dry-001/SERVE (forward=true, trained=false)
#    path embed_mean_pool->mlp0->rms_norm->lm_head when layer-0
#    MLP tensors exist; + weights.safetensors (init if missing)
# Or: ./spark-serve docs/examples/spark-builder.sparkbc /tmp/serve-dry-001
```

### 6c) Serve HTTP / stdio API (G-lane)

Wraps the same tiny CPU forward behind a local JSON API
(predict next-token + embeddings). Attention forward (D-lane) is
not required — uses whatever tensors `serve.py` already runs.
**Not production. Never 6000.**

```bash
# one-shot SERVE dir first (or point --weights at any Spark .safetensors)
./spark-serve docs/examples/spark-builder.sparkbc /tmp/serve-dry-001
make spark-serve-api
./spark-serve-api --weights /tmp/serve-dry-001/weights.safetensors \
  --http --host 127.0.0.1 --port 8765

curl -s http://127.0.0.1:8765/health
curl -s http://127.0.0.1:8765/version
curl -s -X POST http://127.0.0.1:8765/v1/predict \
  -H 'Content-Type: application/json' \
  -d '{"token_ids":[72,105]}'
curl -s -X POST http://127.0.0.1:8765/v1/embeddings \
  -H 'Content-Type: application/json' \
  -d '{"text":"Hi"}'

# stdio (one JSON object per line):
echo '{"op":"predict","token_ids":[1,2]}' | \
  ./spark-serve-api --weights /tmp/serve-dry-001/weights.safetensors \
  --stdio

make test-serve-api
```

Focused TRAIN→STEP→ARTIFACT gate: `make sparkbc-e2e` /
`make test-sparkbc-e2e` (`tools/spark-bc-dump/run_e2e_gate.sh`,
wrapper `scripts/sparkbc-e2e`). Compiles
`examples/spark_train_step.spark`, dumps TRAIN/STEP decode, runs
`./spark-bootstrap --run-bc` **and** `./spark --run-bc`, asserts
`out/train/job-dry-001/ARTIFACT` (`not_sgd=false`, `trained=true`,
`step_n=1`) + `checkpoint.json`. `make test-sparkbc` asserts STEP
weights + `loss_after < loss_before` (multi-outer SGD). **Not beat
Claude.**

Scale proof (SGD then measurement-only eval):

```bash
make spark-sgd-proof
# → prints loss curve + make spark-eval WEIGHTS=… (scores only)
```

**Opt-in larger fixture / dims (local; not GHA default):**

```bash
# 145-pair longer JSONL + dim=64 / n_layer=4 (still CPU-fast)
make spark-sgd-proof-scale
# override knobs:
SPARK_SGD_DIM=64 SPARK_SGD_N_LAYER=4 \
  SPARK_SGD_OUTER=2 SPARK_SGD_INNER=4 \
  make spark-sgd-proof-scale
```

CI / `make spark-sgd-proof` keeps `dataset.jsonl` + `arch_from_bc`
tiny defaults. Scale config SoT:
`examples/fixtures/train/scale_config.json` +
`dataset_scale.jsonl`. Shape checks live in `make test-sparkbc`
(no overnight train). **Not beat Claude.** Never 6000.


## Eval harness (measure later — not beat Claude)

Frozen tiny probes live under `examples/eval/` (copy/recall +
next-token fixtures). Runner: `tools/spark-eval/run.py`.

```bash
make spark-eval
# optional Spark weights (init or later train artifact):
make spark-eval WEIGHTS=docs/examples/spark-self.init.safetensors
# or: SPARK_EVAL_WEIGHTS=/path/to/weights.safetensors make spark-eval
# optional Claude API baseline (skips if no key on box):
make spark-eval-claude
# or: make spark-eval CLAUDE=auto
```

- **Dry** (default): oracle fixture path — prints scores, exits **0**.
- **Weights**: teacher-forced / next-token accuracy on
  `spark.embed` + `spark.lm_head` (CPU only; never the 6000).
- **Claude baseline (optional):** `CLAUDE=auto` / `make spark-eval-claude`
  calls Anthropic **only** when a key already exists
  (`SPARK_EVAL_CLAUDE_API_KEY`, `ANTHROPIC_API_KEY`, `CLAUDE_API_KEY`,
  or `SPARK_EVAL_CLAUDE_KEY_FILE`). Otherwise status
  `skipped_no_credentials`. `CLAUDE=on` fails closed if missing.
  Never invents keys. Never uses the 6000.
- Suite JSON: `examples/eval/suite.json` (`claim: none`).
- Gate: `make test-spark-eval`.

### Eval honesty (Spark / SparkLang)

- Product name in docs and scores: **Spark** / **SparkLang** only.
- Harness output always sets `claim: none` and `beats_claude: false`.
- Side-by-side Spark vs Claude scores are **measurement**, not a
  marketing win. A higher Spark score on tiny fixtures **does not**
  authorize “beats Claude.”
- Dry Spark oracle scores are fixture plumbing, not model quality.
- Weights-mode scores of `0.0` are honest misses until proven otherwise.

## Published files — sha256

Hashes from `sha256sum` on disk at doc authoring time (`51e4dbd` tree).
Re-run `sha256sum` after recompile; mismatch means drift — update this
table from disk, do not invent.

| File | sha256 |
|------|--------|
| [spark-builder.sparkbc](examples/spark-builder.sparkbc) | `e89b27c86618cbbb87d2d59209fb5c0450c0513105c88c622de367f3a8e29f9a` |
| [spark-self.sparkbc](examples/spark-self.sparkbc) | `a33f3232752c2fdd75db728773cb589a4eaf8e0bb70ac2539d2519b2dc7df6e8` |
| [spark-selfhost-train.sparkbc](examples/spark-selfhost-train.sparkbc) | `0b524a96338e13c75efd431853ca33cc8ef227483d3ead0fbb56342da23f9d2b` |
| [spark-train-step.sparkbc](examples/spark-train-step.sparkbc) | `d08925b52bf8c840de626c9cfec619d4dbae5a674b94bb8c7c5837eb1ac64551` |
| [spark-builder-bc.txt](examples/spark-builder-bc.txt) | `dab100c553b8e9f0fc22a3dec02add952d53716566934326a2900364a66610bd` |
| [spark-self-bc.txt](examples/spark-self-bc.txt) | `f9d0021a839c050d37338c2397ab1bd9f2794713ba08f9dfbbfb0e584ce52716` |
| [spark-train-step-bc.txt](examples/spark-train-step-bc.txt) | `6b603e771bb621e3a0534b1c2501867da1bbae286c7104186f7d7d7c7f636036` |
| [spark-self.init.safetensors](examples/spark-self.init.safetensors) | `60b9b7297cb5e2d8362702144a9d9c15487e65dd11783ba7d499499b500198cf` |
| [spark-self-builder.json](examples/spark-self-builder.json) | `44fb6a04e174c562a2dd7efab7307f4500bf8dc91675b3325c9a4aff39e02623` |

## Model lab (in tree)

Flagship: `examples/model_lab.spark` — reverse / inspect → compile plan →
train → modify (`keep_existing`) → abstain / SoT. Runbook:
[MODEL_LAB.md](MODEL_LAB.md).

```bash
./spark --dry-run examples/model_lab.spark
make test-model-lab
```

- `model reverse` / `inspect` — local `config.json` + safetensors **index**
  names only (no tensor body load; no closed-weight theft).
- `model compile` — SPARK_BC **plan** for the `.spark` program (dry stub
  under `out/lab/`). Real bytes: `./spark-bootstrap --compile`.
- `model modify` — attach only; `keep_special_training: true`.
- Lab verbs stay **GAS-first** (no SPARK_BC opcode yet for reverse /
  compile / modify). Train **does** encode as `0x26` / `0x27` / `0x28`.

## Gaps / BLOCKED / later

| Item | Status |
|------|--------|
| GAS emit `.sparkbc` | **implemented** — `./spark --compile` wraps bootstrap |
| GAS `./spark --run-bc` | **implemented** — thin fork → bootstrap bc_vm |
| Dry ARTIFACT / `--run-bc` TRAIN accept | **implemented** — fixture until STEP |
| Init safetensors from SPARK_BC | **implemented** — `trained: false` until STEP |
| STEP CPU SGD weights | **implemented** (multi-outer; `weights.safetensors` + `checkpoint.json` loss curve; `trained=true`; `not_sgd=false`; loss must drop) |
| Tiny CPU serve forward | **implemented** (`dump.py --serve` → `SERVE` with `forward=true`; optional layer-0 MLP; `trained` from weights meta; not production) |
| Serve HTTP / stdio API | **implemented** (`./spark-serve-api` — `/health` `/version` `/v1/predict` `/v1/embeddings`; gate `make test-serve-api`; not production) |
| Beats Claude / production LLM | **not** — multi-stage later; multi-outer SGD ≠ Claude |

| Cloudflare Pages deploy | Prefer Wrangler OAuth (`npx wrangler pages deploy website …`); if CLI/auth absent → **dashboard** upload of `website/` from a known SHA (see [RELEASE.md](RELEASE.md) step 5) |

## Status

| Claim | Today |
|-------|--------|
| Compile Spark → SPARK_BC | **implemented** (`--compile`) |
| Train / step / status ops in the binary | **implemented** (`0x26` / `0x28` / `0x27`) |
| Selfhost train seed `.sparkbc` | **implemented** (`compile_train.spark`) |
| STEP proof stream TRAIN→STEP→TRAIN_STATUS | **implemented** (`spark_train_step.spark`) |
| Execute TRAIN / STEP from published `.sparkbc` | **implemented** (`--run-bc`; STEP = CPU SGD) |
| Focused e2e gate (compile→dump→run-bc→ARTIFACT) | **implemented** (`make sparkbc-e2e` / `make test-sparkbc-e2e`) |
| GAS `./spark --dry-run` train verbs | **implemented** (source, not bytecode) |
| GAS emit `.sparkbc` | **implemented** (`./spark --compile` wrap) |
| GAS `./spark --run-bc` | **implemented** (fork → bootstrap bc_vm) |
| Hex dump + decode | **implemented** (`tools/spark-bc-dump/dump.py`) |
| Emit init weights from those bytes | **implemented** (init only) |
| Round-trip hello SPARK_BC | **tested** (`make test-sparkbc`) |
| Model lab reverse/compile/modify | **tested** (`make test-model-lab`) |
| STEP real CPU SGD | **implemented** (tiny; loss drop proven; not beat Claude) |
| Tiny CPU serve forward | **implemented** (`SERVE`; `forward=true`; not production) |
| Serve HTTP / stdio API (G-lane) | **implemented** (`spark-serve-api`; predict + embeddings; not production) |
| Beats Claude | **not** |


## Related

- Builder page live on production Pages:
  https://sparklang.dev/docs/spark-builder.html
- **Factory hub:** [FACTORY.md](FACTORY.md) /
  https://sparklang.dev/docs/factory.html
- **Diagrams:** [DIAGRAMS.md](DIAGRAMS.md) /
  https://sparklang.dev/docs/diagrams.html
- Engineer factory docs: [COMPILE.md](COMPILE.md) ·
  [DECOMPILE.md](DECOMPILE.md) ·
  [BUILD_MODELS.md](BUILD_MODELS.md) ·
  [TRAIN_LOOP.md](TRAIN_LOOP.md) ·
  [ARCHITECTURE.md](ARCHITECTURE.md) ·
  [ATTENTION_FORWARD.md](ATTENTION_FORWARD.md) ·
  [TOKENIZER.md](TOKENIZER.md) ·
  [SERVE.md](SERVE.md) ·
  [EVAL.md](EVAL.md) ·
  [SPARKBC_MAKE.md](SPARKBC_MAKE.md) ·
  [CI_PAGES.md](CI_PAGES.md)
- [SPARK_BC.md](SPARK_BC.md)
- [MODEL_LAB.md](MODEL_LAB.md)
- [AI_MODELS.md](AI_MODELS.md)
- [LANGUAGE.md](LANGUAGE.md)
- [SELF_HOST.md](SELF_HOST.md)
- [MODEL_TRAINING.md](MODEL_TRAINING.md)
- [ADOPTION_BAR.md](ADOPTION_BAR.md)
- [RELEASE.md](RELEASE.md)
