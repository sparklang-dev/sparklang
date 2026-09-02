# `bootstrap/` — thin C VM (lane B)

**SoT:** dry-run interpreter in `vm.c` → `spark-bootstrap` / `sparkc`.
Isolated from GAS `./spark`. Architecture: [`docs/SELF_HOST.md`](../docs/SELF_HOST.md).

**Honesty:** not a full language runtime; not `--live` product path;
not a wrapper around `./spark` (optional `--compare` harness only).

## Build / test

```bash
make spark-bootstrap
./spark-bootstrap --dry-run examples/hello.spark
make test-bootstrap
```

## Dry ops (proven)

| Area | Ops |
|------|-----|
| Core | `#` / `model` / `ask` / `print` / `let` |
| AI slice | `classify` / `extract` / `tool` / `with tools` / `pipeline` / `\|` |
| Voice | `listen` / `speak` (48-byte RIFF stub) / `voice` session |
| Review | `review path` / `review text` (not `review url`) |
| Browser | `browser run\|open\|start` / `goto` (session.json); `browser show` (show.json); `browser flags` (j_flags JSON); `browser render` / `browser engine render` (layout→paint→show) |
| MITM | `mitm enable` dry JSON (`mitm.json`) |
| Engine | `engine fetch "file://…"` local body; `engine fetch parse`; `engine parse`; `engine css attach` (72B styles: visibility, opacity 0\|1, transparent/yellow/cyan/magenta/orange/lime); `engine layout` (`box_count` 21 on style_basic); `engine paint boxes` (PPM); `engine show` (show.json); `engine render` (layout→paint→show) |

Ask-in-tools → `[tool:NAME] stub:local`. Fail-loud for GUI/`--live`,
cdp, other mitm ops,
remote http(s) without flags mirroring GAS refuse strings.

## Live-only (non-goals for this dry Phase 1)

These stay fail-loud / GAS-scaffold. Do **not** treat dry B as
`--live` product path. Stage 4–5 are **not** done.

- `review url` (path/text only)
- `browser gui` / `browser cdp` (needs `--live` or GAS-only)
- `mitm` beyond dry `enable`
- `engine` remote http(s) / `--live` fetch (needs `--allow-net`)
- IDE buffer chrome / TLS / X11 / Electron

Tree-walk `spark_vm_run_file` is a **deprecated** `--compare`
baseline. Shared dry helpers stay in `bootstrap/engine_*.c` for
later `bc_vm` calls. No new SPARK_BC opcodes this phase.

## Not claimed

- Full GAS op matrix / IDE buffer chrome / full engine pipeline
- TLS / X11 / Electron / full compiler
- Stage 4 (Spark compiles Spark) or Stage 5 (kick the ladder)
