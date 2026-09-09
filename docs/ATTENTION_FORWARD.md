# Attention heads / MLP / serve forward

Honest status of **neural forward** pieces next to SPARK_BC.
Spark / SparkLang only. Documents tip/`main` after **D-lane**
(#28) attention train + serve landed.

## Summary table

| Piece | On tip (`main`) | Notes |
|-------|-----------------|-------|
| Init tensors `spark.layers.*.q/k/v/o` + `attn_norm` | **allocated** | `weights.py` Xavier init from SPARK_BC bytes |
| Init tensors MLP (`mlp_up/gate/down`, `mlp_norm`) | **allocated** | same |
| Tiny CPU serve: embed → **attn0** → optional **MLP0** → RMSNorm → lm_head | **implemented** | `serve.py` / `dump.py --serve` when layer-0 attn tensors exist |
| Tiny CPU serve: attention (last-query causal MHA / GQA) | **implemented** | D-lane; no RoPE math yet |
| `control.sparkasm` ATTN / ROPE macros | **source + shape check** | `make test-sparkasm-control` — not a tensor VM |
| Attention train (factory D-lane) | **implemented** | `apply_sgd_step` default `train_attn=True`; `--no-train-attn` = mean-pool CE |
| HTTP serve API (factory G-lane) | **implemented** | `make spark-serve-api` — see [SERVE.md](SERVE.md) |
| Beat Claude | **not** | never claim from docs |
| RTX PRO 6000 train | **never** | voice-only; 5090 OK |

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

## Attention train (D-lane on tip)

```bash
make spark-sgd-proof
# asserts train_attn, copy_recall>0, next_token>0, beats_claude=false
```

- Module: `python/sparklang/model_lab/attn.py` (last-query causal
  MHA forward + backward).
- SGD: `weights.py` `apply_sgd_step(..., train_attn=True)` via
  `tools/spark-bc-dump/apply_step.py`.
- Eval path uses attn0 when weights present
  (`tools/spark-eval/run.py`).
- Docs: [SPARK_BUILDER.md](SPARK_BUILDER.md). Changelog **0.6.44**.

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

- [SPARK_BUILDER.md](SPARK_BUILDER.md) · [TRAIN_LOOP.md](TRAIN_LOOP.md)
- [SERVE.md](SERVE.md) · [ARCHITECTURE.md](ARCHITECTURE.md)
- [FACTORY.md](FACTORY.md) · [EVAL.md](EVAL.md)
