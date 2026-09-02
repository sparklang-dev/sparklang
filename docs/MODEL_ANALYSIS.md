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
| `spark.toml` / env aliases | `fast`, `code`, `best`, `alias-code` |
| Bifrost-style gateway aliases | when `AI_GATEWAY_URL` set |
| Local listening vLLM (read-only) | e.g. `:8003` local coder |

**Explicitly out of scope / protected:**

- Inventing live leaderboard numbers
- Killing or loading compute on **:8010 / reserved voice GPU**
- Public Bifrost tunnel without a gateway probe credential — on 401:
  report **credential unavailable**, continue with local/dry-run; **do not**
  invent routing conclusions
- `train@*` GPU training — **build** writes blueprint/config only unless
  an owner train-grant is explicit elsewhere (not Spark’s job)

Catalog file: `data/model-catalog.jsonl` (fixture rows ship with the repo;
live probe may append real listen results when `SPARK_ALLOW_NET=1`).

Extension hooks: `[models]` in `spark.toml`, `SPARK_MODEL_*` env, provider
plugins later — document new sources here when added.

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
| `model improve from report prefer quality\|speed\|cost\|local -> blueprint` | Blueprint w/ deltas |
| `model build blueprint into "out/better-model.md"` | Plan + config markdown; `train=false` |

## Live probe (optional)

```bash
make model-probe
# or: SPARK_ALLOW_NET=1 bash tools/model_probe/probe.sh
```

Read-only: list configured aliases + `/proc`/`ss`-style listen hints for
local vLLM ports. Never `systemctl stop` voice units. Bifrost public URL
only with a probe-credential wrap; 401 → credential unavailable.
