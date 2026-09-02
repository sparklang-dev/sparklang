# SPEC — browser_mitm

| Field | Value |
|-------|--------|
| target | x86_64 Linux (Linux / Ubuntu) |
| UI engine | Qt WebEngine (PyQt5) |
| MITM | local CONNECT proxy + dynamic leaf certs |
| CA | `data/ca/ca.pem` + `ca.key` (owner machine) |
| CDP | `127.0.0.1:9222` (`QTWEBENGINE_REMOTE_DEBUGGING`) |
| Inspector | in-window request timeline + HAR export |
| Spark analyze | `make browser-mitm-analyze HAR=…` |

## Security

- Proxy binds **127.0.0.1 only**
- Breakpoints / filters are local UI state
- Do not install CA into NSS/system store without `install-ca.sh`
