# sparklang — JavaScript host embed

Run a `.spark` program from Node. Dry-run is the default.

```bash
node -e "
const { run } = require('./js/sparklang');
const r = run('examples/hello.spark');
process.stdout.write(r.stdout);
if (!r.ok) process.exit(r.returncode);
"
node examples/js/host_embed.js
```

Discovery: `SPARK_BIN`, `./spark`, walk-up from cwd/module, then `PATH`.
Missing binary throws. Live is opt-in (`live: true`).

C FFI: `host/c/sparklang.h`. Handshake: `./spark --embed`.
