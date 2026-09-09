# CI + Cloudflare Pages (contributors)

How factory docs and gates reach **sparklang.dev**. Spark /
SparkLang only. Full release cut: [RELEASE.md](RELEASE.md).

## Local docs regen + check

```bash
make docs-html    # python3 tools/md_to_doc_html.py --all-stale
make docs-check   # regen + --check + tools/test_docs_nav.py
```

Mirror `CHANGELOG.md` into `website/CHANGELOG.html` when cutting a
docs release (site SoT is HTML under `website/`). Sync
`docs/examples/` → `website/docs/examples/` when Builder artifacts
change.

## CI (GitHub Actions)

Workflow: `.github/workflows/sparkbc.yml`.

Typical factory jobs (names may grow — read the YAML):

- `make test-sparkbc`
- `make sparkbc-e2e` / related SPARK_BC gates
- Eval unit gate when present: `make test-spark-eval`
- Serve API gate when G-lane merges: `make test-serve-api`

PRs should keep these green. Docs-only PRs still run
`make docs-check` locally before push.

## Production Pages deploy

Project: **`sparklang-dev`**. Branch: **`production`**.

```bash
# on the tip SHA you are shipping
make docs-html
# mirror CHANGELOG.html if needed
npx wrangler pages deploy website \
  --project-name=sparklang-dev \
  --branch=production \
  --commit-hash="$(git rev-parse HEAD)"
```

**Auth:** Wrangler OAuth on SoapBox is often under
`~/.config/.wrangler/` (leading **dot**). That is not
`~/.config/wrangler/`. Do not invent or print tokens.

If CLI/auth absent → Cloudflare dashboard Direct Upload of
`website/` from the known SHA ([RELEASE.md](RELEASE.md) §5b).

### Spot-check after deploy

- https://sparklang.dev/
- https://sparklang.dev/CHANGELOG.html
- https://sparklang.dev/docs/factory.html
- https://sparklang.dev/docs/model-aspects.html
- https://sparklang.dev/docs/voice.html
- https://sparklang.dev/docs/spark-coder.html
- https://sparklang.dev/docs/weight-gallery.html
- https://sparklang.dev/weight-playground.html
- https://sparklang.dev/docs/spark-builder.html
- https://sparklang.dev/docs/compile.html
- https://sparklang.dev/docs/decompile.html
- https://sparklang.dev/docs/llm-decompile.html
- https://sparklang.dev/docs/knowledge.html
- https://sparklang.dev/downloads.html

Record the Pages deployment id next to the git tip. Tip ≠ live
site: say so if deploy lags.

## Related

- [FACTORY.md](FACTORY.md) · [SPARKBC_MAKE.md](SPARKBC_MAKE.md)
- [RELEASE.md](RELEASE.md) · [SPARK_BUILDER.md](SPARK_BUILDER.md)
