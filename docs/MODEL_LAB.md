# Model lab — reverse, compile, build, modify

SparkLang’s model lab is a **language pipeline**, not a from-scratch
foundation-model trainer.

**Flagship:** `examples/model_lab.spark`

```bash
./spark --dry-run examples/model_lab.spark
make test-model-lab
```

Companion: `./spark-model-lab` (reverse / inspect only).

## What each verb means

| Verb | Does | Does **not** |
|------|------|----------------|
| `model reverse` / `model inspect` | Read local `config.json` + safetensors **index** (tensor *names*) | Steal closed weights; load `.safetensors` bodies; invent hidden sizes |
| `model compile` | Plan/emit SPARK_BC of the **`.spark` program** | Compile a transformer into CUDA kernels |
| `model train` / `model build` | Submit an adapter / overlay / head job | Wipe existing LoRA; bake prices into weights |
| `model modify` | Attach a new adapter + abstain head; `keep_existing` | Delete special training (Rachel LoRA, reply-pack locks, grader rows) |
| `head abstain` + SoT / `expect` | SELECT-before-SAMPLE; inventable facts from tools | Put Wikipedia or hours into weights |

## Keep special training

`model modify` is **attach-only**. Dry fixture JSON always includes
`keep_special_training: true` and `keep_existing: true`. Existing LoRA
paths stay listed. Do not replace `spark/train_rachel_lora.spark`
datasets from this lane. Train grants stay literal owner strings.

## Grounding

Inventable prices / IDs / live counts stay on SoT + HTTP + `expect`,
then gated `head ask`. See [ABSTAIN_HEADS.md](ABSTAIN_HEADS.md) and
[https://sparklang.dev/docs/abstain-heads](https://sparklang.dev/docs/abstain-heads).

Wikipedia / general history belongs in RAG or tools, not CPT into the
receptionist adapter.

## Live reverse

```bash
./spark-model-lab --live reverse --model examples/fixtures/models/tiny-lm
# or a local HF dir you already have:
# ./spark-model-lab --live reverse --model /path/to/Qwen3.6-27B
```

`--live` still does **not** download Hub weights. Missing `config.json`
fails loud.

Real SPARK_BC bytes: `./spark-bootstrap --compile file.spark -o out.sparkbc`
([SELF_HOST.md](SELF_HOST.md)). Dry `model compile` writes a plan stub
under `out/lab/`.

Factory (SPARK_BC dump + Spark-created init weights + TRAIN/STEP
opcodes): [SPARK_BUILDER.md](SPARK_BUILDER.md) — full E2E reproduce
commands, published sha256 table, GAS BLOCKED, dry ≠ trained.
Seed is Spark compiling Spark. Later train aims to beat Claude.
Not trained today. STEP→weights is **implemented** (dry; not SGD).

Focused TRAIN→STEP→TRAIN_STATUS proof:

```bash
make sparkbc-e2e
# alias: make test-sparkbc-e2e
# or:    ./tools/spark-bc-dump/run_e2e_gate.sh
```

Asserts compile matches published `.sparkbc`, dump shows TRAIN/STEP,
`--run-bc` dry JSON, and `out/train/job-dry-001/ARTIFACT`
(`not_sgd=true`, `trained=false`, `step_n=1`). Does **not** invent
SGD. STEP-updated weights are **implemented** (`weights.safetensors`).

## Related

- [SPARK_BUILDER.md](SPARK_BUILDER.md)
- [SPARK_BC.md](SPARK_BC.md)
- [LANGUAGE.md](LANGUAGE.md)
- [MODEL_TRAINING.md](MODEL_TRAINING.md)
- [ABSTAIN_HEADS.md](ABSTAIN_HEADS.md)
- [AI_MODELS.md](AI_MODELS.md)
