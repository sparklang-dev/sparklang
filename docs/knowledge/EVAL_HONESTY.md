# Eval and benchmark honesty

Scores are **instruments**, not trophies. Spark’s frozen harness
records probes and optional Claude baselines — it **never** claims
beat Claude ([EVAL.md](EVAL.md)).

## What benchmarks measure

| Family | Examples | Watch-outs |
|--------|----------|------------|
| Knowledge / MMLU-like | Multi-task exams | Contaminated train data |
| Coding | HumanEval, MBPP | Overfit to unit tests |
| Chat preference | Arena-style Elo | Style bias; judge models |
| Tool / agent | Custom trajectories | Env nondeterminism |
| Decompile | Re-exec, recompile | Pretty ≠ correct |

QLoRA authors noted chatbot benchmarks can mislead
([Dettmers et al.](https://arxiv.org/abs/2305.14314)). Prefer
**paired** comparisons on **frozen** prompts with disclosed judges.

## Honesty rules (Spark)

1. Publish the **probe set** and git SHA.
2. Separate **fixture dry-run** from live gateway calls.
3. Optional frontier baseline = **reference**, not a win claim.
4. Abstain / expect failures are first-class — not hidden.

```mermaid
flowchart TB
  probes[Frozen probes] --> run[spark-eval]
  run --> scores[Numeric scores]
  run --> base[Optional Claude baseline]
  scores --> report[Report only]
  base --> report
  report --> ban[Never "beat Claude" banner]
```

## Related

- [EVAL.md](EVAL.md) — harness
- [ABSTAIN_HEADS.md](ABSTAIN_HEADS.md) — when not to answer
- Decompile metrics skepticism — [DECOMPILE_RE.md](DECOMPILE_RE.md)

Hive home: [KNOWLEDGE.md](KNOWLEDGE.md).
