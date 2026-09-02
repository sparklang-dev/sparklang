# Model analysis methodology (Spark)

Spark can **analyze**, **compare**, **improve**, and **build** AI model
configs as first-class language ops. Default runtime stays the asm VM
(dry-run fixtures). Live HTTP is **optional** (`make model-probe`) and
never required for `make test`.

## What “all models” means

**Not** every model in existence.

**Yes:** all **reachable configured + discovered** endpoints:

| Source | Examples |
|--------|----------|
| `spark.toml` / explicit ids | HF ids, checkpoint paths, configured names |
| Gateway model strings | when `AI_GATEWAY_URL` set (you name them) |
| Local listening vLLM (read-only) | e.g. local coder ports |

**Not:** Bifrost-style alias roulette (inventing gateway aliases from task text).

**Explicitly out of scope / protected:**

- Inventing live leaderboard numbers
- Killing or loading compute on reserved voice-only GPUs
- Public gateway probes without a probe credential — on 401:
  report **credential unavailable**, continue with local/dry-run; **do not**
  invent routing conclusions

Catalog file: `data/model-catalog.jsonl` (fixture rows ship with the repo;
live probe may append real listen results when `SPARK_ALLOW_NET=1`).

**Training** (weights / adapters / checkpoints) is a separate pillar —
see [MODEL_TRAINING.md](MODEL_TRAINING.md). This file covers analyze /
compare / improve / plan only.

## Metrics (definitions)

| Metric | Meaning |
|--------|---------|
| `latency_ms_p50` | Median end-to-end latency for suite prompts (ms) |
| `tokens_per_s` | Output tokens / wall seconds when measurable |
| `quality_proxy` | Suite-defined proxy ∈ [0,1] (not a vendor Elo) |
| `tool_call_json_valid_pct` | % of tool-call turns with parseable valid JSON args |

Dry-run values come from **recorded fixtures** under
`examples/fixtures/models/` and `examples/eval_suite.json`.

## “Show exactly why” (mandatory shape)

Every **compare** / **improve** result must include:

1. **metrics** before/after or per-model (latency, tokens/s, quality proxy)
2. **failure_modes** found
3. **reasons** — concrete strings, e.g.
   `code wins tool-call JSON validity 94% vs 71%`
4. **risks** (improve/build)
5. Banner that numbers are fixtures/heuristics — **not** live leaderboards

## Ops

| Statement | Output |
|-----------|--------|
| `model analyze "id" -> report` | Structured analyze JSON |
| `model analyze all -> report` | Catalog-scope report |
| `model compare […] on suite "…" -> comparison` | Side-by-side + reasons |
| `model improve from report prefer quality\|speed\|cost\|local -> blueprint` | Heuristic blueprint |
| `model plan blueprint into "out/better-model.md"` | Markdown plan only |
| `model train` / `model build` / `model status` | **See [MODEL_TRAINING.md](MODEL_TRAINING.md)** |

## Live probe (optional)

```bash
make model-probe
# or: SPARK_ALLOW_NET=1 bash tools/model_probe/probe.sh
```

Read-only: list configured aliases + `/proc`/`ss`-style listen hints for
local vLLM ports. Never `systemctl stop` voice units. Bifrost public URL
only with a probe-credential wrap; 401 → credential unavailable.
