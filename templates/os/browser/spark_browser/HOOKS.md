# Hook — spark_browser package root

Product layout (`spark-browser/spark_browser/`):

| Module | Role |
|--------|------|
| `__init__.py` | Package marker / version |
| `__main__.py` | CLI: `run`, `ca-init`, `mitm analyze` |
| `app.py` | Qt WebEngine window + proxy wiring |
| `replay.py` | Session / HAR replay helpers |
| `mitm/` | CONNECT proxy, CA leaves, store, analyze |
| `inspector/` | In-window request timeline UI |
| `cdp/` | Remote-debugging notes / helpers |

This HOOKS file is **layout documentation** for `os generate`.
Live MITM/CA implementations stay in the product repo — do not
duplicate them under `templates/os/browser/`.
