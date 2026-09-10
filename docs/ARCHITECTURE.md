# Architecture pieces (honest)

Tiny Spark control stack next to SPARK_BC. Product: **Spark /
SparkLang** only. Tensor names from
`python/sparklang/model_lab/weights.py`. Forward from
`python/sparklang/model_lab/serve.py`. Macro graph:
`examples/models/control.sparkasm`.

## Inventory

| Piece | Init tensors | Used in STEP SGD | Used in serve forward |
|-------|--------------|------------------|------------------------|
| `spark.embed` | **yes** | optional grads (+ attn path) | last-token / mean-pool **yes** |
| `spark.lm_head` | **yes** | **yes** (primary) | **yes** |
| `spark.final_norm` (RMSNorm) | **yes** | via attn path | **yes** (after attn0/MLP0) |
| Layer MLP SwiGLU (`mlp_up/gate/down`, `mlp_norm`) | **yes** | no (serve only) | **MLP0 yes** |
| Layer attn (`q/k/v/o`, `attn_norm`) | **yes** | **layer-0 yes** (D) | **attn0 yes** (D) |
| RoPE / multi-layer / KV cache | sparkasm macros only | **no** | **no** |

## Defaults (tip)

Arch is derived from SPARK_BC bytes (tiny stub). Typical control
shapes match `control.sparkasm` comments (e.g. small `dim`, few
layers, GQA head counts) — **re-read** `weights.py` /
`control.sparkasm` for live numbers; do not invent a 3B claim.

Opt-in larger `dim` / `n_layer` for CPU-fast stubs: **scale fixtures**
(`make spark-sgd-proof-scale`).

## Embed → logits paths

**Serve (implemented, layer-0 attention):**

`embed -> attn0 -> mlp0 -> rms_norm -> lm_head`

(when layer-0 attn tensors exist; else mean-pool → MLP0 path)

**Train STEP (implemented, layer-0 attention):**

last-query causal MHA CE on layer-0 q/k/v/o (+ embed / lm_head).
`--no-train-attn` keeps mean-pool CE.

**sparkasm documented (not a VM):**

full block = pre-norm attn (GQA+RoPE) + SwiGLU MLP — shape-checked
by `make test-sparkasm-control` only. RoPE still **not** in the
Python CPU path.

Detail: [Attention / forward](ATTENTION_FORWARD.md).

## Safetensors meta (honest flags)

Init emit sets `trained: false`, `served: false`, derivation notes
tying tensors to SPARK_BC sha256. STEP updates `trained` only when
SGD applies. Serve writes `SERVE` with `forward=true` and copies
honest `trained` from weights.

## Related

- [Serve](SERVE.md) · [Train loop](TRAIN_LOOP.md)
- [BUILD_MODELS.md](BUILD_MODELS.md) · [Factory hub](FACTORY.md)
