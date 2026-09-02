# SparkLang reference trainer

Minimal HTTP server that implements the train contract used by
`./spark-train-http` (see `docs/MODEL_TRAINING.md` § Trainer HTTP contract).

```bash
python3 tools/spark-train-ref/server.py --host 127.0.0.1 --port 8090
# other terminal:
export SPARK_TRAIN_BACKEND=http
export SPARK_TRAIN_URL=http://127.0.0.1:8090/v1
./spark-train-http --live --submit \
  --dataset examples/fixtures/train/dataset.jsonl \
  --base fixture-base \
  --out out/train/job-live-ref-001
./spark-train-http --live --status <job_id>
```

Creates a real `adapter.bin` (marker bytes) under `--out`. No GPU.
