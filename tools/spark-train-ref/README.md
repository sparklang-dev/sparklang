# SparkLang reference trainer — multi-method CPU train

HTTP server for `./spark --live` / `./spark-train-http`
(see `docs/MODEL_TRAINING.md`).

## Methods (not LoRA)

| Method | What it trains | Primary artifact |
|--------|----------------|------------------|
| `spark_distill_cpu` | Reply-class student | `weights.pt` |
| `spark_pref_pack` | Preference ranker over chosen/rejected | `pref_pack.json` + `ranker.pt` |
| `spark_playbook_fit` | Intent→playbook router | `playbooks.json` + `router.pt` |

Select via POST `method` (or `base` if it matches a method id),
companion `--method`, or env `SPARK_TRAIN_METHOD`.

```bash
python3 tools/spark-train-ref/server.py --host 127.0.0.1 --port 8090
export SPARK_TRAIN_BACKEND=http
export SPARK_TRAIN_URL=http://127.0.0.1:8090/v1

# distill (default)
./spark --live examples/model_train.spark

# preference pack
SPARK_TRAIN_METHOD=spark_pref_pack \
./spark-train-http --live --submit \
  --method spark_pref_pack \
  --dataset examples/fixtures/train/dataset.jsonl \
  --base spark_pref_pack \
  --out out/train/job-pref-001

# playbook fit
SPARK_TRAIN_METHOD=spark_playbook_fit \
./spark-train-http --live --submit \
  --method spark_playbook_fit \
  --out out/train/job-play-001
```

CPU only — never uses a voice-reserved GPU.
