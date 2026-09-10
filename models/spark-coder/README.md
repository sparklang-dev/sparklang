# spark-coder model pack

Reference TinyCoder weights trained in-repo (M-lane). This pack is
the **reference implementation** proving the training pipeline. The
product coder is the self-hosted Qwen3-Coder-30B endpoint (see
`./spark-code status`; `SPARK_CODER_URL`, default
`http://127.0.0.1:8003`) — offline, no API keys.

- `weights.safetensors` — Spark tensors after SGD
- `arch.json` — profile `spark-coder`, config `tiny` (CI default)
- `checkpoint.json` — loss curve (`claim: none`)

## Trainer configs

| Config | Out dir | Command |
|--------|---------|---------|
| tiny (CI default) | `models/spark-coder/` | `make spark-coder-train` |
| large (opt-in) | `models/spark-coder-large/` | `make spark-coder-train-large` |

```bash
make spark-coder-train
./spark-code generate --prompt "..."           # self-hosted 30B
./spark-code generate --engine reference ...   # this pack
make spark-coder-eval-real                     # execution-graded eval
```

Prefer RTX **5090**; never reserved voice GPUs. Trainer config SoT:
`examples/fixtures/coder/scale_config.json`.
