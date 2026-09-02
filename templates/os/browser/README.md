# browser_mitm OS scaffold (Spark-generated)

**Honesty bound:** This tree is a **browser product scaffold + layout
hooks**, not a Chrome fork and **not** a system-wide MITM. Spark never
installs a CA, never reboots this host, and never ships traffic off-box.

Canonical **runnable** product: `~/workspaces/spark-browser`
(Qt WebEngine + local CONNECT proxy). This `out/os/browser_mitm/`
tree is what `os generate` emits from `templates/os/browser/`.

## What you get

| Artifact | Role |
|----------|------|
| `SPEC.md` | Engine, MITM, CDP, security knobs |
| `WHY.md` | Exact why this debug-appliance shape |
| `LAYOUT.md` | Path map ↔ spark-browser layout hooks |
| `Makefile` | Owner hooks (`scaffold`, analyze pointer) |
| `docs/ARCHITECTURE.md` | Proxy / inspector / HAR flow |
| `spark_browser/**/HOOKS.md` | Package layout stubs (not live MITM) |
| `scripts/` `bin/` `tests/` | Hook docs for product-side scripts |
| `data/ca/README.md` | CA dir contract (keys never generated here) |
| `optional/spark_network_hooks.md` | Spark `network analyze` bridge |

## Generate + product

```bash
# From spark/
./spark --dry-run examples/browser_mitm.spark
./spark --dry-run examples/browser_main.spark   # dry SoT (no GUI)
make browser-scaffold
cd ../spark-browser && make run                 # sole live: --live browser/run.spark
```

## Honesty

- MITM applies to **this browser’s traffic only** (127.0.0.1 proxy).
- CA private keys live under `spark-browser/data/ca/` (gitignored).
- System trust only via explicit `scripts/install-ca.sh` (never auto).
- No Speedometer / “10000×” claims without benchmarks.
