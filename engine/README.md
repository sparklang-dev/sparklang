# Spark engine B — HTML tokenizer + DOM (asm)

Language op: `engine parse "…html"` → `out/browser/engine/dom.json`.

```bash
make
./spark --dry-run examples/engine_parse.spark
# or: ./tests/engine_html_parse.sh
```

Implementation: `asm/engine_html.s` (no Chromium, no Qt, no Python).
