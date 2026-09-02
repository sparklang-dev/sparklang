# Architecture — browser_mitm scaffold

```
┌─────────────┐   QNetworkProxy    ┌──────────────────┐
│ Qt WebEngine│ ─────────────────► │ MitmProxy :8877  │
│  + CDP:9222 │                    │ CA leaves        │
└──────┬──────┘                    └────────┬─────────┘
       │                                    │ TLS to origin
       ▼                                    ▼
┌─────────────┐                    ┌──────────────────┐
│ Inspector   │ ◄── SessionStore ──│ request/response │
│ timeline    │                    │ WS frame tap     │
└─────────────┘                    └──────────────────┘
       │
       ▼ HAR → spark_browser mitm analyze → Spark network analyze
```

CA private keys: product `data/ca/` (gitignored). System trust only
via `scripts/install-ca.sh`. Scaffold tree never invents key material.
