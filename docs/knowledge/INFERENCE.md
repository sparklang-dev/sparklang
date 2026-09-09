# Inference — sampling, KV cache, quantization

Training writes weights. **Inference** turns a prompt into tokens
under latency and VRAM budgets.

![Inference path schematic](/docs/images/diagram-knowledge-inference.svg)

## Prefill vs decode

1. **Prefill** — process the full prompt; build per-layer **K** and
   **V** tensors (**KV cache**).
2. **Decode** — for each new token, compute a fresh **Q**, attend to
   cached K/V, append new K/V, sample the next id.

Without a cache, every step would re-attend the whole prefix
(`O(n^2)` blow-ups). Cache memory grows with sequence length ×
layers × heads × dim — hence eviction / restore research
(e.g. [RestoreKV](https://arxiv.org/abs/2608.01247)).

## Sampling

Logits → probabilities → pick a token:

| Knob | Effect |
|------|--------|
| **temperature** | Softens / sharpens the distribution |
| **top-k** | Keep only *k* largest logits |
| **top-p (nucleus)** | Keep smallest set with cumulative mass ≥ *p* |
| **greedy / beam** | Deterministic or search-based (less “chatty”) |

Temperature 0 ≈ argmax. High temperature + open tools = more chaos.

## Quantization

Shrink weight (and sometimes activation/KV) bit-width:

- **GPTQ** — post-training weight quant with Hessian-aware packing
  ([Frantar et al.](https://arxiv.org/abs/2210.17323)).
- **AWQ** — activation-aware channel protection
  ([Lin et al.](https://arxiv.org/abs/2306.00978)).
- **NF4 / QLoRA** — 4-bit NormalFloat for finetune memory
  ([Dettmers et al.](https://arxiv.org/abs/2305.14314)).

Accuracy vs speed is empirical — see ACL 2025 trade-off discussion
([Give Me BF16…](https://aclanthology.org/2025.acl-long.1304/)).

## Spark honesty

Spark **serve** today is a **tiny CPU forward** plus HTTP helpers —
[SERVE.md](SERVE.md). Do **not** read marketing KV-cache claims
into the factory. 5090 OK for GPU experiments; ****.

Next: [Multimodal](MULTIMODAL.md) · [Agents](AGENTS_TOOLS.md) ·
[Attention honesty](ATTENTION_FORWARD.md).
