# Spark eval suite (frozen probes)

Tiny copy/recall + next-token fixtures for `make spark-eval`.

- **Dry** (default): oracle fixture path — prints scores, exit 0.
- **Weights**: `SPARK_EVAL_WEIGHTS=…` or `make spark-eval WEIGHTS=…`.

Does **not** claim beat Claude. See `docs/SPARK_BUILDER.md`
(Compare later). Runner: `tools/spark-eval/`.
