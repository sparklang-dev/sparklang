# Weight gallery — view / play / understand Spark stub weights

Catalog **many weight kinds** Spark already produces (or can emit):
init / dry ARTIFACT, post-STEP SGD, checkpoints, scale
fixtures, owned **spark-coder**, and **large / xl** multi-layer
profiles. Play on CPU; opt-in generate XL on a consumer GPU.
These are tiny-to-xl **control stubs**, not production LLM weights.
Dump/compile stay SoT for SPARK_BC.

Hub: [Factory hub](FACTORY.md). Arch roles: [Architecture](ARCHITECTURE.md).

## Size profiles (tiny → xl)

| Profile | dim | n_layer | Notes |
|---------|-----|---------|-------|
| `tiny` | 32 | 2 | Default init / spark-coder |
| `scale` | 64 | 4 | Scale fixture (`spark-sgd-proof-scale`) |
| `large` | 128 | 8 | Multi-layer + full attn tensor set |
| `xl` | 256 | 8 | Opt-in; consumer GPU suggested |

Larger spark-coder variant path (when present):
`models/spark-coder-large/weights.safetensors`.

## Kind catalog

| Kind | What it is |
|------|------------|
| Init / dry ARTIFACT | SPARK_BC-seeded Xavier; `trained=false` |
| Post-STEP SGD | After `apply_step` / coder train (`lm_head`, embed, attn…) |
| Checkpoints | `checkpoint.json` loss-curve companions |
| Scale fixtures | Larger dim/layers (`spark-sgd-proof-scale`) |
| spark-coder | Owned TinyCoder under `models/spark-coder/` |
| spark-coder-large / gallery large|xl | Larger stub packs |
| `models/**/*.safetensors` | Any owned pack on disk |
| `docs/examples/*.safetensors` | Checked-in init examples |

## View

```bash
make weight-gallery # catalog JSON + sample emits
PYTHONPATH=python python3 tools/spark-weights/cli.py catalog
PYTHONPATH=python python3 tools/spark-weights/cli.py inspect \
 docs/examples/spark-self.init.safetensors
PYTHONPATH=python python3 tools/spark-weights/cli.py explain attn
```

Each tensor row: **name**, **shape**, **dtype** (F32), **sha256**,
**role** (`embed` / `attn` / `mlp` / `lm_head` / `norm` / `other`).

## Play

```bash
# Forward / predict (CPU; works on large/xl stubs too)
PYTHONPATH=python python3 tools/spark-weights/cli.py play \
 docs/examples/spark-self.init.safetensors --prompt "hi"

# Diff norms between two weight files
PYTHONPATH=python python3 tools/spark-weights/cli.py diff A.safetensors B.safetensors

# Histogram / L2 stats (CPU)
PYTHONPATH=python python3 tools/spark-weights/cli.py stats \
 out/gallery/large/weights.safetensors --name spark.embed.weight
```

Website: [/docs/weight-gallery.html](/docs/weight-gallery.html)
and interactive browser [/weight-playground.html](/weight-playground.html)
(loads `docs/examples/weight-gallery-catalog.json`).

## Generate (opt-in large)

```bash
# CPU scale + large samples under out/gallery/
make weight-gallery

# XL on CPU:
PYTHONPATH=python python3 tools/spark-weights/cli.py generate xl --cpu
```

## Understand (roles in the Spark forward path)

| Role | Plain English |
|------|----------------|
| **embed** | Byte/token table; prompt rows → mean-pool or attn0 |
| **attn** | Layer q/k/v/o (+ norm); multi-layer on large/xl |
| **mlp** | SwiGLU up/gate/down; single-layer in tiny CPU serve |
| **norm** | RMSNorm scales before MLP / lm_head |
| **lm_head** | Hidden → vocab logits; primary STEP CE target |

Forward sketch: `embed → attn? → mlp? → rms_norm → lm_head`
([Serve](SERVE.md), [Attention / forward](ATTENTION_FORWARD.md)).

## Make targets

| Target | Role |
|--------|------|
| `make weight-gallery` | Emit scale+large samples, write catalog JSON |
| `make test-weights-play` | Unit + CLI play/diff/stats smoke |
| `make weight-gallery-xl` | Opt-in XL emit |

SDK pack includes checked-in init safetensors + catalog JSON when
present; regenerate large samples via the make targets above (CI
keeps tiny/scale smoke — XL is opt-in).

## Related

- [BUILD_MODELS.md](BUILD_MODELS.md) · [Train loop](TRAIN_LOOP.md)
- [Spark coder](SPARK_CODER.md) · [SPARKBC_MAKE.md](SPARKBC_MAKE.md)
- [Eval](EVAL.md) — measurement only; 