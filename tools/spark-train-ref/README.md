# SparkLang reference trainer

Minimal HTTP server that implements the train contract used by
`./spark --live` / `./spark-train-http` (see `docs/MODEL_TRAINING.md`
§ Trainer HTTP contract).

Writes a **marker** `adapter.bin` under `--out` (filesystem plumbing
proof — not real LoRA / weights). No GPU.

When `out` basename matches `job-*` (e.g. `out/train/job-dry-001`),
`job_id` is that basename so live `model status` (which polls
`job-dry-001`) succeeds.

```bash
python3 tools/spark-train-ref/server.py --host 127.0.0.1 --port 8090
# other terminal:
export SPARK_TRAIN_BACKEND=http
export SPARK_TRAIN_URL=http://127.0.0.1:8090/v1
./spark --live examples/model_train.spark
# companion form still works:
./spark-train-http --live --submit \
  --dataset examples/fixtures/train/dataset.jsonl \
  --base fixture-base \
  --out out/train/job-dry-001
./spark-train-http --live --status job-dry-001
```
