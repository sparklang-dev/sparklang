# Attention heads / MLP / serve forward

Honest status of **neural forward** pieces next to SPARK_BC.
Spark / SparkLang only. Documents tip/`main` after attention train + serve landed.

## Summary table

| Piece | On tip (`main`) | Notes |
|-------|-----------------|-------|
| Init tensors `spark.layers.*.q/k/v/o` + `attn_norm` | **allocated** | `weights.py` Xavier init from SPARK_BC bytes |
| Init tensors MLP (`mlp_up/gate/down`, `mlp_norm`) | **allocated** | same |
| Tiny CPU serve: embed → **attn0** → optional **MLP0** → RMSNorm → lm_head | **implemented** | `serve.py` / `dump.py --serve` when layer-0 attn tensors exist |
| Tiny CPU serve: attention (last-query causal MHA / GQA) | **implemented** | layer-0 attention; no RoPE math yet |
| `control.sparkasm` ATTN / ROPE macros | **source + shape check** | `make test-sparkasm-control` — not a tensor VM |
| Attention train (layer-0) | **implemented** | `apply_sgd_step` default `train_attn=True`; `--no-train-attn` = mean-pool CE |
| HTTP serve API | **implemented** | `make spark-serve-api` — see [Serve](SERVE.md) |
| Optional GPU train | **CPU default** | Prefer consumer GPU (e.g. RTX 5090) when used |

## Serve forward (what exists)

```bash
make spark-serve
./spark-serve docs/examples/spark-builder.sparkbc /tmp/serve-dry-001
# or:
PYTHONPATH=python python3 tools/spark-bc-dump/dump.py \
 docs/examples/spark-builder.sparkbc \
 --serve /tmp/serve-dry-001
```

Writes `SERVE` with `forward=true` and honest `trained` from
weights meta. Path string when layer-0 attn (+ optional MLP)
tensors exist:

`embed->attn0->mlp0->rms_norm->lm_head`

Code: `python/sparklang/model_lab/serve.py` (`_attn_block`,
`_mlp_block`, `run_tiny_forward`) and
`python/sparklang/model_lab/attn.py`. Gate: `make test-sparkbc`
→ `tools/spark-bc-dump/test_dump.py`.

**Not** a production LLM. **Not** multi-layer full-decode /
RoPE. Fixture-scale only.

## Attention train (layer-0 attention on tip)

```bash
make spark-sgd-proof
# asserts train_attn, copy_recall>0, next_token>0, claim=none
```

- Module: `python/sparklang/model_lab/attn.py` (last-query causal
 MHA forward + backward).
- SGD: `weights.py` `apply_sgd_step(..., train_attn=True)` via
 `tools/spark-bc-dump/apply_step.py`.
- Eval path uses attn0 when weights present
 (`tools/spark-eval/run.py`).
- Docs: [SPARK_BC Builder](SPARK_BUILDER.md). Changelog **0.6.44**.

**Not** claiming multi-head production quality or Claude-parity.

## MLP0 (what exists)

Layer-0 SwiGLU-style block on CPU when tensors are present
(CHANGELOG **0.6.32**). Used in serve after attn0 (or mean-pool
when `--no-train-attn` / missing attn tensors). Still fixture-scale.

## SPARK_BC vs tensor asm

| Artifact | Role |
|----------|------|
| `.sparkbc` | Orchestration program (`TRAIN` / `STEP` / …) |
| `control.sparkasm` | Human-readable **forward graph** macros |
| `weights.safetensors` | Numeric tensors (init or STEP) |

Do not call sparkasm “SPARK_BC decompile.”

## Related

- [SPARK_BC Builder](SPARK_BUILDER.md) · [Train loop](TRAIN_LOOP.md)
- [Serve](SERVE.md) · [Architecture](ARCHITECTURE.md)
- [Factory hub](FACTORY.md) · [Eval](EVAL.md)
