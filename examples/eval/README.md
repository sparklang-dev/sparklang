# Spark eval suite (frozen probes)

Tiny copy/recall + next-token fixtures for `make spark-eval`.

- **Dry** (default): oracle fixture path — prints scores, exit 0.
- **Weights**: `SPARK_EVAL_WEIGHTS=…` or `make spark-eval WEIGHTS=…`.
- **Claude baseline (optional):** `make spark-eval-claude` or
  `CLAUDE=auto` — calls Anthropic only if
  `SPARK_EVAL_CLAUDE_API_KEY` / `ANTHROPIC_API_KEY` /
  `CLAUDE_API_KEY` / `SPARK_EVAL_CLAUDE_KEY_FILE` is already set.
  Otherwise status `skipped_no_credentials`. Never invents keys.

Does **not** claim beat Claude. Side-by-side scores are measurement
only (`beats_claude` always false). See `docs/SPARK_BUILDER.md`
(Eval honesty). Runner: `tools/spark-eval/`.
