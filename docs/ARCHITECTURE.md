# Architecture pieces (honest)

Tiny Spark control stack next to SPARK_BC. Product: **Spark /
SparkLang** only. Tensor names from
`python/sparklang/model_lab/weights.py`. Forward from
`python/sparklang/model_lab/serve.py`. Macro graph:
`examples/models/control.sparkasm`.

## Inventory

| Piece | Init tensors | Used in STEP SGD | Used in serve forward |
|-------|--------------|------------------|------------------------|
| `spark.embed` | **yes** | optional grads | mean-pool **yes** |
| `spark.lm_head` | **yes** | **yes** (primary) | **yes** |
| `spark.final_norm` (RMSNorm) | **yes** | no | **yes** (after MLP0) |
| Layer MLP SwiGLU (`mlp_up/gate/down`, `mlp_norm`) | **yes** | no | **MLP0 yes** |
| Layer attn (`q/k/v/o`, `attn_norm`) | **yes** (allocated) | **no** | **no** |
| RoPE / GQA / KV cache | sparkasm macros only | **no** | **no** |

## Defaults (tip)

Arch is derived from SPARK_BC bytes (tiny stub). Typical control
shapes match `control.sparkasm` comments (e.g. small `dim`, few
layers, GQA head counts) — **re-read** `weights.py` /
`control.sparkasm` for live numbers; do not invent a 3B claim.

Opt-in larger `dim` / `n_layer` for CPU-fast stubs may land via
**F-lane**; until merged, CI keeps defaults.

## Embed → logits paths

**Serve (implemented):**

`embed_mean_pool -> mlp0 -> rms_norm -> lm_head`

**sparkasm documented (not a VM):**

full block = pre-norm attn (GQA+RoPE) + SwiGLU MLP — shape-checked
by `make test-sparkasm-control` only.

**Attention train/serve math:** sibling **D-lane** — planned /
in-flight; rebase this page when it merges.

Detail: [ATTENTION_FORWARD.md](ATTENTION_FORWARD.md).

## Safetensors meta (honest flags)

Init emit sets `trained: false`, `served: false`, derivation notes
tying tensors to SPARK_BC sha256. STEP updates `trained` only when
SGD applies. Serve writes `SERVE` with `forward=true` and copies
honest `trained` from weights.

## Related

- [SERVE.md](SERVE.md) · [TRAIN_LOOP.md](TRAIN_LOOP.md)
- [BUILD_MODELS.md](BUILD_MODELS.md) · [FACTORY.md](FACTORY.md)
