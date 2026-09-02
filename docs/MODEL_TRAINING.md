# Model training (SparkLang)

**Training is a first-class language pillar.** `model train` / `model build`
submit jobs via `backend "http"` to a trainer you run at
`SPARK_TRAIN_URL` — not a magic cloud. Dry-run fixtures demonstrate the
path; live requires that service. Optional `model plan` is markdown only.

Eval helpers (`model analyze` / `compare` / `improve`) stay offline
sugar. Optional plan export is `model plan` (markdown). Live gateway
`ask` is **optional** for post-train inference checks — SparkLang is
not a Bifrost plugin.

Full language forms: [LANGUAGE.md](LANGUAGE.md).

## Verbs

| Statement | Meaning |
|-----------|---------|
| `model train … -> job` | Submit a train job (dry fixtures or live backend) |
| `model build …` | **Same as train** (rehabilitated; not blueprint) |
| `model status ["job-id"] -> status` | Poll job state + artifact paths |
| `model plan blueprint into "path"` | Optional markdown plan only |
| `model analyze` / `compare` / `improve` | Eval / heuristic helpers (unchanged) |

Minimal train form (fields optional in dry-run; fixtures fill gaps):

```
model train dataset "data/train.jsonl" base "base-id" out "out/train/demo" backend "http" -> job

model status "job-dry-001" -> status
```

## Job lifecycle

```
submit  →  accepted (job_id)
        →  running
        →  succeeded | failed | cancelled
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
./spark-train-http --dry --status job-dry-001

# Live
export SPARK_TRAIN_BACKEND=http
export SPARK_TRAIN_URL=https://train.example/v1   # your API
# optional: SPARK_TRAIN_TOKEN=…   (never commit)
./spark --live examples/model_train.spark
# or:
./spark-train-http --live --submit \
  --dataset data/train.jsonl --base base-id --out out/train/demo
./spark-train-http --live --status <job_id>
```

Expected HTTP shape (adapter contract):

- `POST {SPARK_TRAIN_URL}/jobs` — body JSON
  `{dataset,base,out,backend}` → `{job_id,status,artifacts}`
- `GET {SPARK_TRAIN_URL}/jobs/{id}` →
  `{job_id,state,artifacts}`

## Trainer HTTP contract

Exact shapes `./spark-train-http` sends and prints (no other endpoints):

### Submit

```
POST {SPARK_TRAIN_URL}/jobs
Content-Type: application/json
Authorization: Bearer {SPARK_TRAIN_TOKEN}   # optional

{"dataset":"…","base":"…","out":"…","backend":"http"}
```

Response body (printed to stdout as-is):

```
{"job_id":"…","status":"accepted","artifacts":{"adapter":"…","checkpoint":"…","marker":"…"}, …}
```

`status` is the submit ack (`accepted`). Extra fields are allowed.

### Status

```
GET {SPARK_TRAIN_URL}/jobs/{job_id}
Authorization: Bearer {SPARK_TRAIN_TOKEN}   # optional
```

Response body:

```
{"job_id":"…","state":"succeeded|failed|running|…","artifacts":{…}, …}
```

`state` is the poll field (not `status`). Companion uses plain HTTP
(TLS must terminate upstream for `https://` — MVP dies with a clear
config error).

### Reference trainer (in-repo)

`tools/spark-train-ref/server.py` implements this contract and writes a
real `adapter.bin` marker under `--out`. Live capture (recorded):

[website/docs/examples/live-train-capture.txt](../website/docs/examples/live-train-capture.txt)

```bash
python3 tools/spark-train-ref/server.py --host 127.0.0.1 --port 8090
export SPARK_TRAIN_BACKEND=http
export SPARK_TRAIN_URL=http://127.0.0.1:8090/v1
./spark-train-http --live --submit \
  --dataset examples/fixtures/train/dataset.jsonl \
  --base fixture-base \
  --out out/train/job-live-ref-001
```

Not a GPU train — filesystem artifacts only.
### local-yield (optional; gated)

Only when **all** hold:

1. `SPARK_TRAIN_BACKEND=local-yield`
2. Unit name is in `SPARK_TRAIN_UNIT_ALLOWLIST` (comma-separated)
3. Operator has a real owner train-grant for that unit elsewhere —
   Spark **does not** invent train-grant tokens

Then the companion may run `systemctl start train@<unit>`. Training
compute policy on shared hosts: coding GPU only via the yield unit;
never place Spark training on a voice-only GPU.

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
```

`make test` never starts GPU jobs or dials the network.

## Not in MVP

- Auto dataset curation / labeling UI
- Hugging Face Hub publish
- Full LoRA studio / multi-node scheduler UI
- Invented owner train-grant strings
- Bifrost alias pickers as “Step 2” of building a model
