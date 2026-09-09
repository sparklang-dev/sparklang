# spark-coder model pack

Owned TinyCoder weights trained in-repo (M-lane).

- `weights.safetensors` — Spark tensors after CPU SGD
- `arch.json` — profile `spark-coder`
- `checkpoint.json` — loss curve (`beats_claude: false`)

Regenerate:

```bash
make spark-coder-train
```

Never 6000. Not a downloaded base model.
