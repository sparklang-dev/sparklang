# spark-eval

Frozen probe harness for Spark weights (or dry fixtures).

```bash
make spark-eval
make spark-eval WEIGHTS=docs/examples/spark-self.init.safetensors
# or: SPARK_EVAL_WEIGHTS=/path/to/weights.safetensors make spark-eval
```

Prints per-probe scores. Exit **0** when the harness runs
(measurement ≠ win claim). Does **not** claim beat Claude.

Suite: `examples/eval/suite.json`.
