# SparkLang Language Server / editor support

Editor language support for `.spark` — hover, completion, and
diagnostics. Prefer this over homegrown IDE chrome for authoring.

**Product:** Spark / SparkLang only.

## What ships

| Piece | Path | Role |
|-------|------|------|
| Keyword catalog | `tools/spark_lsp/keywords.json` | Shared hover / completion |
| Static analyze | `tools/spark_lsp/analyze.py` | Unclosed strings; unbound `expect` |
| Stdio LSP | `tools/spark_lsp/server.py` | Minimal JSON-RPC language server |
| VS Code-compatible editors extension | `tools/spark-ide-extension/` | TextMate + providers + `--check` diags |

## Commands

```bash
# Diagnose one file (CI-friendly JSON)
python3 tools/spark_lsp/server.py --check examples/expect_pass.spark

# Gate
make test-spark-lsp

# Extension (from repo root; symlink or copy into ~/.vscode/extensions)
# Open any .spark → hover / completion / diagnostics on save
```

Stdio server (Neovim / other LSP clients):

```bash
python3 tools/spark_lsp/server.py
```

Capabilities: `textDocumentSync`, `hoverProvider`,
`completionProvider`, `publishDiagnostics`.

## Diagnostics

| Code | Severity | Meaning |
|------|----------|---------|
| `unclosed-string` | Warning | Odd `"` count on a non-comment line |
| `expect-unbound` | Error | `expect … NAME` without `let` / `-> NAME` |

Does **not** run the Spark VM. Does **not** replace `make test-expect`.
Not a claim of full semantic analysis.

## Related

- [IDE.md](IDE.md) — language `ide` ops + GUI
- [sdk-ide-download](/docs/sdk-ide-download.html) — pack download
- [LANGUAGE.md](LANGUAGE.md) — statement reference
- [ADOPTION_BAR.md](ADOPTION_BAR.md) — LSP preferred over IDE chrome
