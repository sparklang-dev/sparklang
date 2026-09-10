# Eval harness (measurement only)

Frozen probes for Spark weights. Exit 0
means the harness ran — not a marketing win. Never invents API keys.
Prefer CPU or a consumer GPU for train. Code:
`tools/spark-eval/`. Suite: `examples/eval/`.

## Commands

```bash
make spark-eval
make spark-eval WEIGHTS=docs/examples/spark-self.init.safetensors
# or: SPARK_EVAL_WEIGHTS=/path/to/weights.safetensors make spark-eval

make test-spark-eval
```

After SGD proof:

```bash
make spark-sgd-proof # ends with spark-eval on those weights
```

## Modes

| Mode | Behavior |
|------|----------|
| Dry (default) | Oracle fixture path; prints scores; exit 0 |
| Weights | Teacher-forced / next-token on `spark.embed` + `spark.lm_head` (CPU) |

## Eval contract
- Suite JSON `claim: none`.
- Harness sets `claim: none` (no marketing-win flag).
- Side-by-side Spark vs frontier-API scores are **measurement**.
- Dry oracle scores ≠ model quality.
- Weights-mode `0.0` scores are misses until proven otherwise.
- Product name in prose: **Spark** / **SparkLang** only.

## Related

- [SPARK_BC Builder](SPARK_BUILDER.md) § Eval harness
- `tools/spark-eval/README.md`
- [Train loop](TRAIN_LOOP.md) · [Factory hub](FACTORY.md)
- [SPARKBC_MAKE.md](SPARKBC_MAKE.md)
