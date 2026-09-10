# spark-eval

Frozen probe harness for Spark weights (or dry fixtures), with an
optional frontier-API baseline when credentials already exist.

```bash
make spark-eval
make spark-eval WEIGHTS=docs/examples/spark-self.init.safetensors
# optional frontier-API head-to-head (skips cleanly if no key on box):
make spark-eval-frontier
# or: make spark-eval FRONTIER=auto
# force require key: make spark-eval FRONTIER=on
```

Prints per-probe Spark scores and, when the frontier baseline runs, a
side-by-side comparison table. Exit **0** when the harness runs
(measurement ≠ win claim). Exit **2** only if `FRONTIER=on` and no
credentials / API error.

Never invents API keys. Never uses
the 6000.

Suite: `examples/eval/suite.json`.
Tests: `make test-spark-eval`.
