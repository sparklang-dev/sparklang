# Site infra fix — 2026-09-10

Scope: the two infrastructure P0s from the read-only sparklang.dev
audit, plus the generator-code-only slugify fix. No website content
pages or docs HTML touched (other lanes own those); docs HTML regen
intentionally not run (later pass owns it).

PR: https://github.com/sparklang-dev/sparklang/pull/60
(`feat/site-infra-fix`, commit `a903dfa`) — CI `sparkbc` green
(17m53s), merged as `69e75c2` under merge authority v3.

## P0-2 — deploy diagnosis (what was actually wrong)

The Cloudflare Pages project **`sparklang-dev` is direct-upload** —
verified two ways: `wrangler pages project list` shows no git
provider, and the REST API returns `source: null`. There is no
git-connected build to fail or pause; every production deploy is a
manual `wrangler pages deploy` from whatever local checkout the
deployer happened to be in, and **last upload wins**.

Byte-level state matched that exactly: the most recent production
deployment (`caa9b561`, ~11h before the fix) was uploaded with
`--commit-hash e8bd42e` — a commit **6+ behind main** that predates
`0ac2b10` (LSP page + nav), `007cb8b` (tone scrub), and PRs #55/#56.
Three deploys landed within the same hour from three different
commits (`e8bd42e`, `7b8d8c6`, `fafe28f` — all ancestors of main),
i.e. parallel sessions each deploying their own stale checkout; the
oldest tree uploaded last, so the live site rolled backwards. That
is why `a5e9f07`'s `spark-self.init.safetensors` was live (present
in `website/` since #4) while the newer LSP page 200'd the homepage:
not a mixed deploy — one old full tree, deployed last.

The earlier `a5e9f07` file loss ("dropped by docs rsync") was the
same family one level down: a **filtered** sync into `website/`
before upload. Full-tree uploads cannot drop files; filtered
pre-syncs can.

## P0-2 — the fix

- `tools/deploy-site.sh` — the single canonical deploy path. One
  atomic full-tree `wrangler pages deploy website/
  --project-name=sparklang-dev --branch=production
  --commit-hash=<HEAD>` per run. No rsync filters, no partial syncs.
  Refuses a dirty `website/` tree (`--allow-dirty` overrides) and a
  HEAD that is not an ancestor of `origin/main`
  (`--allow-unmerged` overrides). `--dry-run` prints the plan.
- `make deploy-site` target.
- `docs/CI_PAGES.md` — deploy section rewritten: direct-upload
  reality, the incident, the script, and the owner-side upgrade
  paths (Pages↔GitHub integration needs the dashboard GitHub App
  flow; an Actions deploy workflow needs a `CLOUDFLARE_API_TOKEN`
  repo secret — neither is CLI/API-provisionable, so merge-to-main
  auto-deploy is documented, not faked).

Guard paths verified locally: dirty tree → exit 1 with the offending
files; `--allow-dirty --dry-run` → prints plan, uploads nothing.

## P0-2 — atomic deploy of merged main (authorized close of merged PRs)

Deployed `origin/main` tip `69e75c2` (worktree detached at the merge
commit; `website/` tree identical to the PR tip — verified empty
diff):

- **Deployment id: `fbfa6b30-f491-4bb1-8251-7f5a4c7833fe`**
- URL: https://fbfa6b30.sparklang-dev.pages.dev
- Source recorded on the deployment: `69e75c2` (merged main tip)
- Upload: 150-file manifest, 109 new assets + 41 content-addressed
  already present (wrangler dedup — the manifest is the full tree).

## Live verification (curl, cache-busted, after the deploy)

| Check | Before | After |
| --- | --- | --- |
| `/definitely-not-a-page-xyz123` | HTTP 200, 27712 B homepage (soft-404) | **HTTP 404**, 9620 B, `<title>Page not found — SparkLang</title>` |
| `/docs/lsp.html` | 200 serving homepage bytes (page missing) | 308 → `/docs/lsp` → **HTTP 200, 14419 B**, `<title>Language server / editor — Spark</title>` (exact worktree bytes) |
| `/about` | 12760 B (stale) | **200, new build** — 11264 B live vs 11330 B on disk; diff is only Cloudflare zone email-obfuscation stripping 4 `<!--email_off-->` comment lines (pre-existing zone feature, not deploy drift) |
| `/sitemap.xml` | did not exist | **HTTP 200**, 62 `<url>` entries |
| `/robots.txt` | did not exist | **HTTP 200**, `Allow: /` + sitemap reference |
| `/docs/examples/spark-self.init.safetensors` | 200 | still **200** (191766 B) |
| `/CHANGELOG` ElevenLabs mentions (PRs #55/#56 marker) | present | **0** — tone scrub live |
| `/` | 27712 B | 200, 23437 B (new build) |

## P0-1 — soft-404 files (new)

- `website/404.html` — site shell (same header/nav/footer as
  `index.html`, managed `spark-primary-nav` block so
  `sync_site_nav.py` keeps it in sync — `--check` passes), honest
  "Page not found", links to `/`, `/docs/language.html`,
  `/downloads.html`, `noindex`. Pages serves it automatically for
  misses (verified above).
- `website/robots.txt` — allow all + sitemap reference.
- `website/sitemap.xml` — 62 real pages enumerated from the file
  list (excludes `404.html` and `try.html`, which `_redirects`
  301s). Canonical **extensionless** URLs because Pages 308s
  `.html` → pretty (verified: `/docs/factory.html` → 308
  `/docs/factory`); `index.html` → directory form; `lastmod` from
  `git log -1 --format=%as` per file (all 62 resolved).

## P0-3 — slugify GitHub parity (code only)

`tools/md_to_doc_html.py` `slugify()` collapsed whitespace runs
(`[\s_]+` → `-`) and stripped edge dashes, so "Published files —
sha256" became `published-files-sha256` while docs authors link the
GitHub-rendered anchor `published-files--sha256` (GitHub removes the
em-dash as punctuation and turns each surrounding space into its own
dash). Fixed to github-slugger parity: strip tags → unescape →
lower → remove non-`[^\w\s-]` → **each** whitespace char → `-`, no
collapsing, no edge strip, underscore kept (it is a word char).

Full-corpus scan (every published `docs/*.md`, every fragment link,
old vs new algorithm):

- **9 queued anchors fixed**: model-aspects in-page ×6
  (`ears--stt--audio-in`, `eyes--vision--image-in`,
  `speaking--tts--audio-out`, `thinking--llm-forward--generation`,
  `behaviors--policies-tools-turn-taking`,
  `system-diagram--ears--brain--voice--tools`), spark-builder
  `published-files--sha256`, native-network-web → language.html
  `#network` and `#browser--mitm-language-sot`.
- **0 existing links regress** (no link relied on collapsed ids).
- 1 link stays broken and is **source-side, not slugify**:
  MODEL_ASPECTS.md links
  `#comparison--spark-local-sot-vs-openbin-ask--phone-voice` but the
  heading reads "…/ production voice stacks" — content lane owns.

Tests: `tools/test_md_slugify.py` (4 tests: 9 real parity cases,
5 stable-id regressions, HTML/entity stripping, underscore-kept),
wired into `make docs-check`. Results: **4/4 OK**; existing
`tools.test_docs_nav` **9/9 OK**. Docs HTML **not** regenerated —
the later regen pass picks the new ids up.

## Merge state

- PR #60 merged `69e75c2` (CI green). This report is the follow-up
  commit on the same branch.
- Live site = merged main, one atomic deployment
  (`fbfa6b30-f491-4bb1-8251-7f5a4c7833fe`). Mixed-version state is
  gone.
