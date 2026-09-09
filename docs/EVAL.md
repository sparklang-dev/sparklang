# Eval harness (measurement only)

Frozen probes for Spark weights. **Does not beat Claude.** Exit 0
means the harness ran — not a marketing win. Never invents API keys.
Never uses the RTX PRO 6000.

Optional Claude API baseline is **merged** on tip. Code:
`tools/spark-eval/`. Suite: `examples/eval/`.

## Commands

```bash
make spark-eval
make spark-eval WEIGHTS=docs/examples/spark-self.init.safetensors
# or: SPARK_EVAL_WEIGHTS=/path/to/weights.safetensors make spark-eval

# Optional Claude API baseline:
make spark-eval-claude
# or: make spark-eval CLAUDE=auto
# require key: make spark-eval CLAUDE=on

make test-spark-eval
```

After SGD proof:

```bash
make spark-sgd-proof   # ends with spark-eval on those weights
```

## Modes

| Mode | Behavior |
|------|----------|
| Dry (default) | Oracle fixture path; prints scores; exit 0 |
| Weights | Teacher-forced / next-token on `spark.embed` + `spark.lm_head` (CPU) |
| Claude baseline | Anthropic Messages **only if** a key already exists on the box |

Credential env / file names (read `tools/spark-eval/claude_baseline.py`
or SPARK_BUILDER eval section — do not invent):
`SPARK_EVAL_CLAUDE_API_KEY`, `ANTHROPIC_API_KEY`, `CLAUDE_API_KEY`,
or `SPARK_EVAL_CLAUDE_KEY_FILE`. No key →
`skipped_no_credentials`. `CLAUDE=on` fails closed if missing.

## Honesty contract

- Suite JSON `claim: none`.
- Output `beats_claude` always **false**.
- Side-by-side Spark vs Claude scores are **measurement**.
- Dry oracle scores ≠ model quality.
- Weights-mode `0.0` scores are honest misses until proven otherwise.
- Product name in prose: **Spark** / **SparkLang** only.

## Related

- [SPARK_BUILDER.md](SPARK_BUILDER.md) § Eval harness
- `tools/spark-eval/README.md`
- [TRAIN_LOOP.md](TRAIN_LOOP.md) · [FACTORY.md](FACTORY.md)
- [SPARKBC_MAKE.md](SPARKBC_MAKE.md)
