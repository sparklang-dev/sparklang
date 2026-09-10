# spark-eval

Frozen probe harness for Spark weights (or dry fixtures), with an
optional frontier-API baseline when credentials already exist.

```bash
make spark-eval
make spark-eval WEIGHTS=docs/examples/spark-self.init.safetensors
# optional Claude head-to-head (skips cleanly if no key on box):
make spark-eval-claude
# or: make spark-eval CLAUDE=auto
# force require key: make spark-eval CLAUDE=on
```

Prints per-probe Spark scores and, when Claude runs, a side-by-side
comparison table. Exit **0** when the harness runs (measurement ≠ win
claim). Exit **2** only if `CLAUDE=on` and no credentials / API error.

Never invents API keys. Never uses
the 6000.

Suite: `examples/eval/suite.json`.
Tests: `make test-spark-eval`.
