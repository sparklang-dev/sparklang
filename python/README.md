# sparklang — Python host embed

Run a `.spark` program from Python. Dry-run is the default
(fixtures, offline). Live is opt-in.

```bash
# From the SparkLang repo root (after `make`):
PYTHONPATH=python python -c "
from sparklang import run
r = run('examples/hello.spark')
print(r.stdout)
assert r.ok
"
```

```python
from sparklang import run

# Path (dry-run)
r = run("examples/hello.spark")
print(r.returncode, r.stdout)

# Inline source
r = run('print "hi from host"\n')
r.check()

# Live (needs AI_GATEWAY_URL / backends as documented)
# r = run("examples/ask_live.spark", live=True)
```

Discovery: `SPARK_BIN`, `./spark`, walk-up from cwd/package, then
`PATH`. Missing binary → `SparkBinNotFound` (fail loud).

**Not shipped:** JavaScript `require` / C FFI — still `[next]`.
Handshake: `./spark --embed` prints JSON advertising this package.
