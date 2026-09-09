# Attention heads / MLP / serve forward

Honest status of **neural forward** pieces next to SPARK_BC.
Spark / SparkLang only. Sibling lanes own train/serve math and
HTTP API code — this page **documents** tip/`main`, it does not
reimplement them.

## Summary table

| Piece | On tip (`main`) | Notes |
|-------|-----------------|-------|
| Init tensors `spark.layers.*.q/k/v/o` + `attn_norm` | **allocated** | `weights.py` Xavier init from SPARK_BC bytes |
| Init tensors MLP (`mlp_up/gate/down`, `mlp_norm`) | **allocated** | same |
| Tiny CPU serve: embed → **MLP0** → RMSNorm → lm_head | **implemented** | `serve.py` / `dump.py --serve` / `./spark-serve` |
| Tiny CPU serve: **attention** (QKVO / GQA / RoPE) | **not** | tensors exist; forward path skips attn |
| `control.sparkasm` ATTN / ROPE macros | **source + shape check** | `make test-sparkasm-control` — not a tensor VM |
| Attention train / serve math (factory D-lane) | **planned / in-flight** | document when merged; do not claim early |
| HTTP serve API (factory G-lane) | **planned / sibling** | link code when on tip; not invented here |
| Beat Claude | **not** | never claim from docs |

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
weights meta. Path string when MLP tensors exist:

`embed_mean_pool->mlp0->rms_norm->lm_head`

Code: `python/sparklang/model_lab/serve.py` (`_mlp_block`,
`run_tiny_forward`). Gate: `make test-sparkbc` →
`test_serve_forward` in `tools/spark-bc-dump/test_dump.py`.

**Not** a production LLM. **Not** multi-layer attn decode.

## Attention heads (what exists vs planned)

**Exists today**

1. **Weight names** for a tiny control stack — `attn_norm`, `q`,
   `k`, `v`, `o` per layer in init safetensors
   (`python/sparklang/model_lab/weights.py`).
2. **sparkasm documentation** of GQA + RoPE + `ATTN` macros in
   `examples/models/control.sparkasm` (checked by
   `sparkasm_check.py`).
3. Optional lab inspect of **index** names via model reverse.

**Not on tip**

- Running attention in `serve.py` / SGD STEP (STEP trains
  `lm_head` / optional embed — not attn blocks).
- Claiming multi-head train quality or Claude-parity.

When D-lane attention land merges to `main`, rebase this page and
cite the makefile / module paths — do not invent opcodes.

## MLP0 (what exists)

Layer-0 SwiGLU-style block on CPU when tensors are present
(CHANGELOG **0.6.32**). Used in serve after mean-pool embed.
Still fixture-scale.

## SPARK_BC vs tensor asm

| Artifact | Role |
|----------|------|
| `.sparkbc` | Orchestration program (`TRAIN` / `STEP` / …) |
| `control.sparkasm` | Human-readable **forward graph** macros |
| `weights.safetensors` | Numeric tensors (init or STEP) |

Do not call sparkasm “SPARK_BC decompile.”

## Related

- [ARCHITECTURE.md](ARCHITECTURE.md) · [SERVE.md](SERVE.md)
- [Build models](BUILD_MODELS.md) · [Compile](COMPILE.md)
- [SPARK_BUILDER.md](SPARK_BUILDER.md) § serve
- [SPARKBC_MAKE.md](SPARKBC_MAKE.md) · [FACTORY.md](FACTORY.md)
- [ABSTAIN_HEADS.md](ABSTAIN_HEADS.md) (IDK heads — separate product surface)
