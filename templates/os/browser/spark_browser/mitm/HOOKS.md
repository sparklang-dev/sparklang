# Hook — spark_browser.mitm

Product: `spark-browser/spark_browser/mitm/`

| File | Role |
|------|------|
| `proxy.py` | Local CONNECT MITM on 127.0.0.1:8877 (+ CONNECT-UDP 501) |
| `ca.py` | Owner CA + dynamic leaf certs |
| `store.py` | Session request/response + WS frames |
| `h2_bridge.py` | ALPN h2 terminate + upstream h2/h1 |
| `quic/` | HTTP/3 MITM (aioquic) — Spark `mitm quic smoke` helper |
| `analyze.py` | HAR → Spark `network analyze` bridge |
| `__init__.py` | Package exports |

## Language CA ops (Spark SoT)

| Spark op | Helper |
|----------|--------|
| `mitm ca-init` | `./spark-mitm-ca --init` → `ensure_ca` |
| `mitm ca-status` | `./spark-mitm-ca --status` |
| `mitm ca-install` | dry-run plan; `--live` → `install-ca.sh` |

## Invariants

- Bind **127.0.0.1 only** (this browser’s traffic).
- Never auto-install CA into NSS/system trust.
- **Language SoT** is Spark `browser`/`mitm` ops (asm); this tree is
  the helper product.
- Scaffold emits this HOOKS.md only — not working CA/proxy code.
