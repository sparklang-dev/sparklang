# CI + Cloudflare Pages (contributors)

How factory docs and gates reach **sparklang.dev**. Spark /
SparkLang only. Full release cut: [RELEASE.md](RELEASE.md).

## Local docs regen + check

```bash
make docs-html # python3 tools/md_to_doc_html.py --all-stale
make docs-check # regen + --check + tools/test_docs_nav.py
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
- Serve API gate when serve API path merges: `make test-serve-api`
- Voice easy dry: `make test-voice-easy`

PRs should keep these green. Docs-only PRs still run
`make docs-check` locally before push.

## Production Pages deploy

Project: **`sparklang-dev`**. Branch: **`production`**.
The project is **direct upload** (no git integration — verified
2026-09-10: API `source: null`). Deploys are therefore manual;
the canonical path is the atomic full-tree script:

```bash
# on the tip SHA you are shipping (merged to main, clean tree)
make docs-html   # only when docs/*.md changed — regen is its own lane
# mirror CHANGELOG.html if needed
make deploy-site   # == tools/deploy-site.sh
```

`tools/deploy-site.sh` runs exactly one
`wrangler pages deploy website --project-name=sparklang-dev
--branch=production --commit-hash=<HEAD>` — the **whole** `website/`
tree, every time. No rsync filters, no partial syncs, no per-file
picks. It refuses a dirty `website/` tree (`--allow-dirty` overrides)
and a HEAD that is not on `origin/main` (`--allow-unmerged`
overrides). Pages deployments are immutable bundles, so the site
flips atomically.

**Why (2026-09-10 incident):** ad-hoc manual deploys from stale
local checkouts rolled sparklang.dev ~6 commits backwards (last
upload wins), and a filtered docs rsync once dropped
`spark-self.init.safetensors`. One script, full tree, merged-tip
only — that class of drift cannot happen.

**Upgrade path (owner-side, not CLI-able):** connecting the Pages
project to GitHub (merge-to-main = auto deploy) requires the
Cloudflare GitHub App flow in the dashboard; a GitHub Actions
deploy workflow would need a `CLOUDFLARE_API_TOKEN` repo secret
(not provisioned). Until one of those exists, run
`make deploy-site` after each merge to main.

**Auth:** Wrangler OAuth on the deploy host is often under
`~/.config/.wrangler/` (leading **dot**). That is not
`~/.config/wrangler/`. Do not invent or print tokens.

If CLI/auth absent → Cloudflare dashboard Direct Upload of
`website/` from the known SHA ([RELEASE.md](RELEASE.md) §5b).

### Spot-check after deploy

- https://sparklang.dev/
- https://sparklang.dev/CHANGELOG.html
- https://sparklang.dev/docs/factory.html
- https://sparklang.dev/docs/model-aspects.html
- https://sparklang.dev/docs/voice-easy.html
- https://sparklang.dev/docs/voice.html
- https://sparklang.dev/docs/spark-coder.html
- https://sparklang.dev/docs/weight-gallery.html
- https://sparklang.dev/weight-playground.html
- https://sparklang.dev/docs/spark-builder.html
- https://sparklang.dev/docs/compile.html
- https://sparklang.dev/docs/decompile.html
- https://sparklang.dev/docs/decompile-compete.html
- https://sparklang.dev/docs/llm-decompile.html
- https://sparklang.dev/docs/knowledge.html
- https://sparklang.dev/docs/knowledge-safety.html
- https://sparklang.dev/data/decompile-scoreboard.json
- https://sparklang.dev/downloads.html
- **Images MIME (required):**
 `curl -sI https://sparklang.dev/docs/images/decompile-cli-dump.png?v=0.6.58`
 must show `Content-Type: image/png` (not `text/html`).
 SVG: `…/diagram-spark-loop.svg` → `image/svg+xml` only
 (no dual `text/html`). `nosniff` + wrong MIME = blank screenshots.

Record the Pages deployment id next to the git tip. Tip ≠ live
site: say so if deploy lags.

## Related

- [Factory hub](FACTORY.md) · [SPARKBC_MAKE.md](SPARKBC_MAKE.md)
- [RELEASE.md](RELEASE.md) · [SPARK_BC Builder](SPARK_BUILDER.md)
