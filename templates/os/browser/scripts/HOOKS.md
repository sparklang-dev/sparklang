# Hook — scripts/

Product: `spark-browser/scripts/`

| Script | Role |
|--------|------|
| `launch.sh` | Start browser + MITM + CDP defaults |
| `install-ca.sh` | Explicit user NSS / optional `--system` trust |

Never invoke `install-ca.sh` from Spark `os generate` or agents.
Owner-driven only.
