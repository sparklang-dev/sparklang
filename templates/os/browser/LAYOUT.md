# LAYOUT — templates/os/browser ↔ spark-browser

`os generate` copies this template into `out/os/browser_mitm/`.
Runnable code lives in `~/workspaces/spark-browser`. Hooks below map
1:1 to product paths; **do not** treat HOOKS.md as executable MITM.

| Template path | Product path | Role |
|---------------|--------------|------|
| `README.md` | `README.md` / `docs/spark-README.md` | Honesty + launch |
| `SPEC.md` | `docs/spark-SPEC.md` | Engine / ports / CA |
| `WHY.md` | `docs/spark-WHY.md` | Exact why |
| `docs/ARCHITECTURE.md` | `docs/ARCHITECTURE.md` | Proxy diagram |
| `Makefile` | `Makefile` | run / test / ca-init / analyze |
| `.gitignore` | `.gitignore` | CA keys + sessions |
| `spark_browser/HOOKS.md` | `spark_browser/` | Package root |
| `spark_browser/mitm/HOOKS.md` | `spark_browser/mitm/` | proxy / ca / store / analyze |
| `spark_browser/inspector/HOOKS.md` | `spark_browser/inspector/` | timeline UI |
| `spark_browser/cdp/HOOKS.md` | `spark_browser/cdp/` | remote debugging |
| `scripts/HOOKS.md` | `scripts/launch.sh`, `install-ca.sh` | Owner scripts |
| `bin/HOOKS.md` | `bin/spark-browser-mitm-analyze` | HAR analyze CLI |
| `tests/HOOKS.md` | `tests/test_smoke.py` | Headless smoke |
| `data/ca/README.md` | `data/ca/` | CA dir (keys gitignored) |
| `optional/spark_network_hooks.md` | Spark `network` ops | HAR → analyze |

## Kind separation

| Kind | Templates | Emit |
|------|-----------|------|
| `ai_agent` | `templates/os/ai_agent/` | `out/os/agentos/` |
| `browser` | `templates/os/browser/` | `out/os/browser_mitm/` |

Never copy AgentOS boot/kernel stubs into a browser generate.
