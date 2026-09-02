# data/ca — CA directory contract

Language SoT: Spark `mitm ca-init` (asm → `./spark-mitm-ca --init`)
writes real `ca.pem` / `ca.key` / `ca.meta.json` under
`spark/out/browser/ca/` and syncs product `spark-browser/data/ca/`.

Product `make ca-init` remains a thin alias of the same helper.
Those files are **gitignored**. Trust: `mitm ca-install` with
`--live` only (never auto).

This scaffold directory documents the layout only. Spark `os generate`
must **never** invent or copy private key material into `out/os/`.
