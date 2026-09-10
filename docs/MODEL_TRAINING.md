# Model training (SparkLang)

**Training is a first-class language pillar.** `model train` / `model build`
submit jobs via `backend "http"` to a trainer you run at
`SPARK_TRAIN_URL` — not a magic cloud. Dry-run fixtures demonstrate the
path; live requires that service. Optional `model plan` is markdown only.

Eval helpers (`model analyze` / `compare` / `improve`) stay offline
sugar. Optional plan export is `model plan` (markdown). Live gateway
`ask` is **optional** for post-train inference checks — SparkLang is
not tied to a single AI gateway.

Full language forms: [LANGUAGE.md](LANGUAGE.md).
Factory / SPARK_BC bytecode train ops (`0x26` / `0x28` / `0x27`) and
published proofs: [SPARK_BC Builder](SPARK_BUILDER.md).

## Verbs

| Statement | Meaning |
|-----------|---------|
| `model train … -> job` | Submit a train job (dry fixtures or live backend) |
| `model build …` | **Same as train** (rehabilitated; not blueprint) |
| `model step "job-id" -> step` | Dry loop tick (SPARK_BC `STEP` `0x28`; not SGD) |
| `model reverse` / `inspect` | Local published architecture (config + index names) |
| `model compile` | SPARK_BC plan for the `.spark` program |
| `model modify keep_existing …` | Attach adapters/heads; keep special training |
| `model status ["job-id"] -> status` | Poll job state + artifact paths |
| `model plan blueprint into "path"` | Optional markdown plan only |
| `model analyze` / `compare` / `improve` | Eval / heuristic helpers (unchanged) |

Minimal train form (fields optional in dry-run; fixtures fill gaps):

```
model train dataset "data/train.jsonl" base "base-id" out "out/train/demo" backend "http" method "spark_distill_cpu" -> job

model status "job-dry-001" -> status
```

`method "…"` is optional (`spark_distill_cpu` default). Live GAS forwards
the statement with `./spark-train-http --spark-line`. Status polls the
**quoted** job id from the line (not a hardcoded `job-dry-001`).

## Job lifecycle

```
submit → accepted (job_id)
 → running
 → succeeded | failed | cancelled
artifact paths appear on accept (planned) and again on success
```

| Phase | Dry-run | Live |
|-------|---------|------|
| Submit | Fixture accept JSON; write marker under `out/train/<job_id>/` | Backend adapter |
| Status | Fixture `succeeded` + same paths | Poll backend |
| GPU / net | **Never** | Only when configured |

## Backends (`train.backend` / `SPARK_TRAIN_BACKEND`)

| Id | Role |
|----|------|
| `http` | **Default MVP.** POST job JSON to `SPARK_TRAIN_URL`; poll status |
| `local-yield` | Optional host adapter: `systemctl start train@<unit>` when allowlisted |
| `huggingface` | Reserved id — not wired in MVP (do not claim Hub publish) |

Generic interface — SparkLang is not hard-wired to one machine.

### HTTP (shipped companion)

```bash
# Offline (CI / make test)
./spark-train-http --dry --submit
./spark-train-http --dry --submit --method spark_pref_pack
./spark-train-http --dry --status job-dry-001

# Live
export SPARK_TRAIN_BACKEND=http
export SPARK_TRAIN_URL=https://train.example/v1 # your API
# optional: SPARK_TRAIN_TOKEN=… (never commit)
# optional: SPARK_TRAIN_METHOD=spark_distill_cpu|spark_pref_pack|spark_playbook_fit|spark_faq_index|spark_reply_pack
# optional: SPARK_TRAIN_OUT=out/train/job-… (live out override)
./spark --live examples/model_train.spark
# or:
./spark-train-http --live --submit \
 --method spark_pref_pack \
 --dataset data/train.jsonl --base spark_pref_pack \
 --out out/train/demo
./spark-train-http --live --status <job_id>
```

## Trainer HTTP contract

Exact shapes `./spark-train-http` sends and prints (no other endpoints):

### Submit

```
POST {SPARK_TRAIN_URL}/jobs
Content-Type: application/json
Authorization: Bearer {SPARK_TRAIN_TOKEN} # optional

{"dataset":"…","base":"…","out":"…","backend":"http","method":"spark_distill_cpu"}
```

Response body (printed to stdout as-is):

```
{"job_id":"…","status":"accepted","artifacts":{…},"method":"…", …}
```

`status` is the submit ack (`accepted`). Extra fields are allowed.
`method` selects the training algorithm (see below). If omitted, the
reference trainer may also treat a matching `base` as the method id.

### Status

```
GET {SPARK_TRAIN_URL}/jobs/{job_id}
Authorization: Bearer {SPARK_TRAIN_TOKEN} # optional
```

Response body:

```
{"job_id":"…","state":"succeeded|failed|running|…","artifacts":{…},"method":"…", …}
```

`state` is the poll field (not `status`). Companion uses plain HTTP
(TLS must terminate upstream for `https://` — MVP dies with a clear
config error).

## Reference methods (in-repo) — not LoRA

`tools/spark-train-ref/` implements the HTTP contract with **four**
SparkLang-native CPU methods. None are LoRA / HF PEFT. None use a
reserved GPU. None invent `train@` grants.

| Method | One sentence | Primary artifacts |
|--------|--------------|-------------------|
| `spark_distill_cpu` | Tiny student learns which teacher reply class matches each user turn | `weights.pt` (+ `checkpoint.json`) |
| `spark_pref_pack` | Build chosen/rejected preference pairs and train a tiny ranker | `pref_pack.json` + `ranker.pt` |
| `spark_playbook_fit` | Fit an intent→playbook router from reply templates | `playbooks.json` + `router.pt` |
| `spark_faq_index` | Build FAQ corpus and train a tiny dual-encoder retriever | `faq_index.json` + `encoder.pt` |
| `spark_reply_pack` | Overlay **text + spoken** replies on a base that has **no voice**, or lock major behaviors. Inventable facts require SoT — fail loud, never fabricate | `replies.json` + `gate.json` + `router.pt` |

Select via (first match wins):

1. Language `method "…"` on `model train` / `model build` (live
 `--spark-line`)
2. Companion `--method` / POST body `method` / env `SPARK_TRAIN_METHOD`
3. Or `base` equal to a method id (reference trainer only)
4. Default: `spark_distill_cpu`

Unknown method → fail loud (exit 2). Dry status for an unknown job id
→ fail loud (no silent `job-dry-001`).

HTTP `artifacts.adapter` remains a **compat alias** to the method’s
primary weight file (not a LoRA adapter).

When `out` basename matches `job-*`, that basename is the `job_id`.

Live captures:

- Distill: [website/docs/examples/live-train-capture.txt](../website/docs/examples/live-train-capture.txt)
- All four: [website/docs/examples/live-train-methods-capture.txt](../website/docs/examples/live-train-methods-capture.txt)

```bash
python3 tools/spark-train-ref/server.py --host 127.0.0.1 --port 8090
export SPARK_TRAIN_BACKEND=http
export SPARK_TRAIN_URL=http://127.0.0.1:8090/v1

# method comes from the .spark line
./spark --live examples/model_train.spark
./spark --live examples/model_train_pref.spark
./spark --live examples/model_train_playbook.spark
./spark --live examples/model_train_faq.spark
./spark --live examples/model_train_reply.spark
```

Dry-run fixtures still plan stub paths without training.

### local-yield (optional; gated)

Only when **all** hold:

1. `SPARK_TRAIN_BACKEND=local-yield`
2. Unit name is in `SPARK_TRAIN_UNIT_ALLOWLIST` (comma-separated)
3. Operator has a real owner train-grant for that unit elsewhere —
 Spark **does not** invent train-grant tokens

Then the companion may run `systemctl start train@<unit>`. Training
compute policy on shared hosts: GPU training only via the training
unit above; never on devices reserved for other workloads.

## What `model build` means now

| Old (removed) | New |
|---------------|-----|
| Write `out/*.md` blueprint, `train=false` | Submit train job / print artifacts |

Blueprint markdown → **`model plan`**.

## Dry proof

```bash
./spark --dry-run examples/model_train.spark
# expect: "op":"train", job-dry-001, out/train/job-dry-001
test -f out/train/job-dry-001/ARTIFACT
./spark-train-http --dry --submit | grep job-dry-001
./spark-train-http --dry --submit --method spark_pref_pack | grep spark_pref_pack
./spark-train-http --dry --submit --method spark_faq_index | grep spark_faq_index
./spark-train-http --dry --submit --method spark_reply_pack | grep spark_reply_pack
./spark --dry-run examples/model_train_reply.spark

# SPARK_BC STEP stream (TRAIN → STEP → TRAIN_STATUS)
make sparkbc-e2e
# compile → dump → --run-bc dry → ARTIFACT (not SGD; STEP weights via test-sparkbc)
```

`make test` never starts GPU jobs or dials the network.

## Product story

Spark ships **multiple** CPU training methods behind one HTTP contract —
distill, preference pack, playbook fit, FAQ index, **reply pack**.
`spark_reply_pack` is how you teach **voice and text replies** to a
model that has **no voice**, or **change major behaviors** (greeting,
transfer, IDK) without LoRA. Inventable rows need a SoT file; missing
SoT **fails loud** (no fabricated hours/prices/IDs). That is the
product story: not LoRA-by-default, not a marker file pretending to be
weights. Larger full-SFT / multi-node remain advanced backends behind
the same contract.

## Voice + text overlay (`spark_reply_pack`)

Dataset JSONL may add fields on each chat row:

| Field | Role |
|-------|------|
| `channel` | `text` \| `voice` \| `both` (default `both`) |
| `speak` | Spoken script (defaults to assistant text) |
| `behavior` | Named lock (`greeting`, `hours`, `transfer`, `idk`, …) |
| `lock` | `true` = overlay **wins** over the base model |
| `inventable` | Fact that must not be open-decoded |
| `sot_ref` | **Required** when inventable (path to SoT JSON) |
| `idk` | Halt string when SoT is missing at serve time |
| `wav` | Optional path reference (not a neural clone) |

A **text-only** base still gets a speak channel: Spark `speak reply`
uses the pack script. This is **not** voice-GPU / LoRA TTS training.

Inventable without `sot_ref` → trainer exit error
(`refuse fabricate`). Gate artifact `gate.json` always has
`no_fabricate: true` and `abstain_on_inventable: true`.

Example: `examples/model_train_reply.spark` +
`examples/fixtures/train/reply_pack.jsonl`.

## Not in MVP

- Auto dataset curation / labeling UI
- Hugging Face Hub publish
- Full LoRA studio / multi-node scheduler UI
- Invented owner train-grant strings
- the AI gateway alias pickers as “Step 2” of building a model
- Language-level `method "…"` keyword on `model train` (use env / companion)
