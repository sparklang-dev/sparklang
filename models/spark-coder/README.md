# spark-coder model pack

Owned TinyCoder weights trained in-repo (M-lane).

- `weights.safetensors` — Spark tensors after SGD
- `arch.json` — profile `spark-coder`, scale `tiny` (CI default)
- `checkpoint.json` — loss curve (`beats_claude: false`)

## Tiny (default) vs large (opt-in)

| Scale | Out dir | Command |
|-------|---------|---------|
| tiny | `models/spark-coder/` | `make spark-coder-train` |
| large | `models/spark-coder-large/` | `make spark-coder-train-large` |

```bash
make spark-coder-train
./spark-code scales
./spark-code train --scale large --device auto \
  --out models/spark-coder-large
```

Prefer RTX **5090**; never RTX PRO **6000**. Does not beat Claude.
SoT: `examples/fixtures/coder/scale_config.json`.
