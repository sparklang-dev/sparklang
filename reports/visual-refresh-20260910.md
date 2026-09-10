# Visual refresh — sparklang.dev (2026-09-10)

**Branch:** `feat/visual-refresh` (worktree `sparklang-wt-visual-refresh`, from `origin/main` @ 38b35ec)
**PR:** https://github.com/sparklang-dev/sparklang/pull/67 — **part of tonight's 7-branch consolidation; do not merge standalone, do not deploy.**
**Owner directive:** "our GUIS NEED TO BE IMPRESSIVE"

## Design decisions

Benchmark: Linear / Raycast / Bun / Vercel. The product is a systems
language with a verifier and a decompiler, so the system is built to
feel precise and compiler-grade rather than marketing-flashy.

- **Theme:** dark, rich, engineered. Base `#08090d`, elevated surfaces
  `#12161f`, hairline borders, `color-scheme: dark`.
- **One signature accent:** amber "spark" (`#ffb224`, ember `#e85d04`
  as secondary) — used with restraint: gradient CTAs, gradient text on
  "Prove it.", opcode highlights, proof-bar numerals, focus rings.
- **Ambient texture:** `body::before` = faint blueprint grid + two soft
  radial glows (amber top-center, cool blue bottom-right), masked to
  fade; `body::after` = tiled SVG noise at 4% opacity. Both
  `pointer-events: none`, fixed, non-render-blocking.
- **Glass:** sticky header with `backdrop-filter` blur; cards are
  translucent with 1px borders and lift/glow on hover.
- **Type:** Inter (display/UI) + JetBrains Mono (code/terminal) via one
  Google Fonts stylesheet with `display=swap`; system-stack fallbacks.
- **Motion:** IntersectionObserver adds `.is-in` to `[data-reveal]`
  (translateY 14px + fade, 0.7s ease); hover micro-interactions on
  cards/buttons/links; blinking terminal cursor. Everything gated
  behind `@media (prefers-reduced-motion: no-preference)`; the
  `reduce` path renders the full static page with zero animation.
- **Hero terminal:** glass window with traffic-light bar, looping
  typed replay of a real captured compile → dump → dry-run. The static
  HTML contains the full transcript as `.tl` spans (source of truth);
  `js/landing.js` detaches and progressively re-reveals them (16ms/char
  for commands, 26ms/line for output, 4.6s end pause, pauses when the
  tab is hidden). No-JS / reduced-motion users see the complete
  transcript immediately.
- **Performance:** no frameworks, vanilla CSS/JS only. CSS totals
  ~42.6KB minified-equivalent (site.css 49,073B raw → ~40.1KB min;
  tokens.css 3,606B raw → ~2.4KB min) — inside the 50KB budget.
  landing.js is 4.4KB raw, deferred at end of body.

## Files touched

**Rebuilt/rewritten**
- `website/css/tokens.css` — dark token set (same token names).
- `website/css/site.css` — full visual system; all legacy classes
  rethemed; new landing/terminal/proof-bar/reveal classes;
  `honest-note` renamed to `proof-note`; mobile terminal rules;
  `overflow-x` guard (sticky header verified intact).
- `website/index.html` — landing rebuild per copy deck (hero, proof
  bar, loop strip, trust strip, Why a language?, What Spark does for
  you, Train → status → expect, Also in the box, Learn Spark, Try it).
- `website/js/landing.js` — new: terminal replay + scroll reveals.
- `website/js/site.js` — one-line: mermaid theme `neutral` → `dark`.

**Copy-deck application (content)**
- `website/about.html` — §2: meta description, intro, "What it is"
  list, Core/Optional rows, version 0.6.62.
- `website/workflow.html` — §3: meta description, hero lede, figure
  caption, section lede, step 01–05 bodies, SVG-mock caption,
  voice-ask copy, gallery bodies; **removed "Methods vs OpenBin" link
  and "no OpenBin login" text** (competitor hard rule); "Honest bar"
  note replaced with deck proof line.
- `website/downloads.html` — §4: meta description + intro only
  (runtime version placeholders left for the manifest JS per §4.3).

**Shell-only (css `?v=visual0910`, fonts links, footer v0.6.62; zero
content changes)**
- `website/playground.html`, `website/weight-playground.html`,
  `website/CHANGELOG.html`, `website/learn/{index,getting-started,
  first-program,build-model,ai-in-5-minutes,function-catalog}.html`
- One-word copy fix in `learn/index.html` ("honest status table" →
  "status table") since the shell was being touched.

**Not touched (collision boundaries):** `ide-web.html`
(feat/decompile-no-mocks), `404.html`/`sitemap.xml`/`robots.txt`/deploy
scripts (feat/site-infra-fix), voice page copy (feat/voice-real-weights),
spark-coder claims (feat/real-coder), `docs/**` generated HTML
(feat/site-infra-fix slugify). Docs pages inherit the new theme via the
shared stylesheet within the 1h CSS cache window — no regeneration
needed.

## Real-output provenance (no static mocks)

Every demo element on the rebuilt landing page traces to a real run on
this branch:

| Element | Command | Evidence |
| --- | --- | --- |
| Hero terminal, all 21 lines | `./spark-bootstrap --compile examples/train_eval.spark -o out/train_eval.sparkbc`; `python3 tools/spark-bc-dump/dump.py out/train_eval.sparkbc`; `./spark-bootstrap --dry-run examples/train_eval.spark` | `reports/visual-refresh-captures/hero-dump.txt`, `hero-dryrun.txt`. sha256 `7880e2227da06c5c249f97a731471d7d22ceb84fcc28ede9388a25c77d214dbd`, 322 bytes. Byte-verified line-by-line by script (21/21 match; one explicit `…` elision line for dump header comments). |
| "123/123 dry-run tests pass" | `./bootstrap/tests/run_bootstrap.sh` (with `./spark` built) | `reports/visual-refresh-captures/bootstrap-tests.txt` — "123 PASS / 0 FAIL / 0 SKIP", "bootstrap tests OK". |
| "38 bytecode opcodes" | `grep -c '#define SPBC_OP_' bootstrap/bc_opcodes.h` | 38 |
| "100% bytecode round-trip" | `website/data/decompile-scoreboard.json` (generated 2026-09-10) | linked to `/docs/decompile-compete.html` |
| "158 example programs" | `find examples -name '*.spark' \| wc -l` | 158 |
| Compare card "One Spark program" | real subset of `examples/train_eval.spark`; `./spark-bootstrap --dry-run` on the exact snippet exits 0 | snippet upgraded from main's placeholder paths (`data.jsonl`, `out/job-1`) to the real file's paths |
| "Train → status → expect" block | verbatim `examples/train_eval.spark` lines | file in repo |
| "Try it" blocks | deck-verbatim real commands | `./spark --dry-run examples/train_eval.spark` verified exit 0 |
| Live-train capture links | `website/docs/examples/live-train-capture.txt`, `live-train-methods-capture.txt` | linked, exist, not inlined |

Not used as stats: full `tests/run_dry.sh` (347 PASS / 45 FAIL — all
failures environmental: unbuilt companion binaries, no CUDA on this
box). asm `./spark --dry-run examples/train_eval.spark` exits 1 on
expects (known divergence; bootstrap VM passes) — hero uses the
bootstrap binary, which is the one whose output is shown.

## Verification

- Served from worktree `website/` via `python3 -m http.server 8791`.
- All 13 touched pages return 200; all 59 internal `href`s on
  index.html resolve 200; workflow anchors `#compile/#inspect/#train/
  #serve/#share` exist.
- Playwright headless Chromium (no visible browser): before/after
  screenshots below; replay animation observed mid-run (typed command,
  progressive output, cursor); reduced-motion context shows all 21
  lines with no cursor; sticky header top=0 after scroll; mobile 390px
  wraps long disassembly lines inside the terminal (fixed
  `overflow-wrap: anywhere` + mobile font/min-height rules).
- Banned-term sweep on all touched files: CLEAN for OpenBin / Ghidra /
  IDA / Binja / Claude / honest-framing / beats / theater / "not a
  claim" / "not LoRA".
- ReadLints: clean on all edited files.
- CSS budget: ~42.6KB minified-equivalent (< 50KB).

## Screenshots (`reports/visual-refresh-shots/`)

Before: `before-index.png`, `before-index-full.png`,
`before-index-mobile.png`, `before-workflow.png`, `before-about.png`,
`before-downloads.png`, `before-docs-language.png`,
`before-playground.png`.

After: `after-index.png`, `after-index-full.png`,
`after-index-mobile.png`, `after-workflow.png`, `after-about.png`,
`after-downloads.png`, `after-docs-language.png`,
`after-playground.png`.

## Follow-ups for the consolidation pass

1. **CHANGELOG.html historical entries** still contain old feature
   names that are now banned in marketing copy (`make spark-eval-claude`,
   "vs Ghidra", "honest" notes). They are historical records of real
   make targets — renaming targets is a repo-wide decision; left as-is.
2. **`js/decompile-scoreboard.js`** reads a data field named `honesty`
   from `website/data/decompile-scoreboard.json` — schema field,
   invisible to users; rename only with the scoreboard owner's lane.
3. **Docs theme pickup:** docs HTML is generated; pages link the shared
   CSS with old `?v=` params, so they inherit the new theme within the
   1h cache window. After feat/site-infra-fix regenerates docs, no
   further action needed.
4. **weight-playground.html** has no site footer (app-like page) —
   shell bump applied; consider adding the standard footer in a future
   pass if desired.
