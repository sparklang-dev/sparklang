# browser_mitm blueprint (Spark)

Educational / product-scaffold notes for an **owner-local** debug
browser with built-in HTTPS MITM. Not a claim of beating Chrome on
Speedometer. Not a system-wide intercept.

## Product path

Canonical runnable tree: `~/workspaces/spark-browser`

```bash
# From spark/
./spark --dry-run examples/browser_mitm.spark
./spark --dry-run examples/browser_main.spark
make browser-scaffold
cd ../spark-browser && make run   # → ./spark --live browser/run.spark
```

## Engine

**Qt WebEngine (PyQt5)** — Chromium-based, CDP via
`QTWEBENGINE_REMOTE_DEBUGGING`, already packaged on Ubuntu Linux
(no multi-week Chromium compile).

## Honesty

- MITM is for **this browser’s traffic only**, on Michael’s machine.
- CA private keys under `spark-browser/data/ca/` (gitignored).
- System trust only via explicit `scripts/install-ca.sh` (never auto).
- No silent exfil; no shipping others’ traffic off-box.
