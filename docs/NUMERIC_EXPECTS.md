# Numeric + structured expects

Keep `expect equal` / `expect contains`. Additions:

| Form | Meaning |
|------|---------|
| `expect gte NAME $.path N` | JSON path ≥ N |
| `expect lte NAME $.path N` | JSON path ≤ N |
| `expect eq NAME $.path V` | JSON path equals V (`true`/`false`/num/str) |
| `expect histogram_min NAME CLASS N` | `class_histogram[CLASS] ≥ N` |
| `expect score NAME $.path using "URL" >= N` | OpenAI-compatible rubric score |

Dry-run score reads `examples/fixtures/eval/want_score.txt`.
Live score needs `SPARK_EXPECT_TOKEN` (opt-in).
