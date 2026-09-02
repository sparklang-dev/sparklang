# SparkLang — notes for coding agents

**IDE language ops are real** (`ide new|open|save|run|buffer` and
`ide keys` / `ide key` — see [docs/IDE.md](docs/IDE.md)). Paint =
`make test-ide-paint` PPM wire, not a `.spark` op. Do **not** invent
further ops or UI.

Primary docs: [docs/PROGRAMMING_GUIDE.md](docs/PROGRAMMING_GUIDE.md).

This file helps agents in an interim editor workspace. Cursor (or any
IDE) is not the product IDE chrome. **Not** Apache Spark / Databricks.

## Docs

- [docs/PROGRAMMING_GUIDE.md](docs/PROGRAMMING_GUIDE.md) — program with Spark (CLI)
- [docs/IDE.md](docs/IDE.md) — verified `ide` ops + interim editor notes

## Live `ask` (optional)

Default is dry-run / offline. Live OpenAI-compatible gateway only when
the operator sets `AI_GATEWAY_URL` (and a Bearer key via env). Never
commit keys.

## Source

https://github.com/sparklang-dev/sparklang · site https://sparklang.dev/
