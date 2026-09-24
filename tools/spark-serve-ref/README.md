# spark-serve-ref

CPU HTTP helper server for SparkLang `model serve helper`.

```bash
python3 tools/spark-serve-ref/server.py \
  --helper out/pref-001 --name ranker --port 8091 --mode shadow

# dry plan (no bind)
python3 tools/spark-serve-ref/server.py \
  --helper out/pref-001 --dry
```

Endpoints: `GET /health`, `GET /version`, `POST /v1/rank`,
`POST /replay` (Trainer contract). Shadow mode appends
`out/voice_loop/serve-shadow.jsonl` and does not treat rank as truth.
