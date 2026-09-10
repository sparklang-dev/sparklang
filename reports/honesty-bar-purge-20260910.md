# Honesty bar purge — sparklang.dev (2026-09-10)

**Lane:** `fix/honesty-bar-purge` (worktree
`/home/mike/workspaces/sparklang-wt-honesty-purge`; main checkout
untouched per isolation order).
**PR:** [#66](https://github.com/sparklang-dev/sparklang/pull/66) —
CI green (sparkbc, 10m40s) → **merged**.
**Merge SHA:** `d2b4d63` (merge commit of PR #66; branch tip
`34ba94e`).
**Deploy:** DONE — `npx wrangler pages deploy website
--project-name=sparklang-dev --branch=production
--commit-hash=d2b4d63` from a temp detached worktree at the merge
SHA (deploy worktree removed after). Pages deployment:
`92b13cbf.sparklang-dev.pages.dev` (57 uploaded / 95 already
present). Documented path per `docs/CI_PAGES.md`; not improvised.

## Owner directives enforced

1. **"Honesty bar" genre removed, not reworded** — the live
   `## Scope` (formerly "Honesty bar") section on
   `/docs/factory` and every sibling honesty/status block are
   deleted outright. No replacement status boxes.
2. **Zero Claude mentions** in public-facing source and served
   pages.
3. **Zero internal ops/agent jargon** in public copy: GPU train
   policy, RTX 5090 / RTX PRO 6000 placement, "voice-reserved",
   "on tip", "dry/live gated", "planned stub", MLP0 / layer-0 /
   last-query MHA / RoPE internals, `make spark-coder-train` /
   `make voice-easy` as status copy, "multi-outer", "frozen eval".

## Sections deleted in full

| Where | What |
|---|---|
| `docs/FACTORY.md` | `## Scope` (the live "Honesty bar" content: Multi-outer / TinyCoder / "still not Claude" / dry-live gated / planned stub / RoPE / GPU train policy) and `## Factory feature status` (all "**On tip** —" rows; redundant with the Map table) |
| `docs/BUILD_MODELS.md` | `## Honest bar` |
| `docs/SPARK_CODER.md` | `## Honest capability` (2 Claude mentions + broken bullet) |
| `docs/research/LLM_DECOMPILE.md` | `- Honest bar: … GPU train: see factory policy.` bullet |
| `website/workflow.html` | `<p class="honest-note">Honest bar: …</p>` block |
| `website/CHANGELOG.html` | `Claude eval baseline (honest)` `<li>` (its only entry) + the emptied `<h2>0.6.40</h2>` heading |
| `website/css/site.css` | two dead `.honest-note` rules (class no longer used anywhere) |
| `docs/SPARK_BUILDER.md` | `make spark-eval-claude` / `CLAUDE=auto` command lines + "frontier-API baseline (optional)" bullet + "Spark vs Claude scores" bullet |
| `docs/EVAL.md` | spark-eval-claude / CLAUDE command lines, "frontier-API baseline" Modes row, CLAUDE credential-env paragraph |
| `docs/SPARKBC_MAKE.md` | `make spark-eval-claude` reference row + command-block line + "reserved voice GPUs" Never-row |
| `docs/DIAGRAMS.md` | mermaid `CLAUDE` node + `EVAL --> CLAUDE` edge |
| `docs/MODEL_ASPECTS.md` | "Place Spark factory train on GPUs reserved for other voice products" bullet; "**6000** \| **Never** for train" row |

## Reworded (jargon → plain English), same facts

- "multi-outer" → "multi-pass" (status/claims copy; `outer/inner`
  kept only where documenting actual CLI flags in TRAIN_LOOP).
- "layer-0 / last-query MHA / MLP0 / attn0 / RoPE" → "single-layer
  causal attention / the MLP / attention / rotary" or dropped.
- GPU policy copy → "CPU (default) or a consumer GPU" everywhere;
  all "RTX 5090", "6000", "voice-reserved", "reserved voice GPUs",
  "voice GPU" phrasing removed from public copy.
- "on tip" → "included" / "yet" / deleted; "Also on tip" homepage
  heading → "Also included".
- "dry/live gated" → "gated live"; "planned stub" → "not
  available" (vision/eyes facts preserved as plain prose).
- `make spark-coder-train[-large]` / `make voice-easy` in feature
  and how-to copy → `./spark-code train --scale tiny|large` /
  `./spark-voice easy` product CLIs.
- "Honest:" / "Honest status/scope/gaps/limits/checklist" headings
  and prefixes → plain headings ("Status", "Gaps", "Limits",
  "Checklist") or deleted.
- `website/CHANGELOG.html`: 24 entries de-jargoned (historical
  entries kept, banned words removed).
- 9 SVG diagrams under `docs/images/` de-jargoned (regen copies
  them to `website/docs/images/`).
- `tools/md_to_doc_html.py`: 5 injected meta descriptions cleaned
  ("honest status table", "honest limits", "HF/Claude substitute",
  "MLP0 serve forward", "Multi-outer").
- Data artifacts: `decompile-scoreboard.json` ×3 (`honesty` key →
  `note`, "reserved voice GPUs" → "reserved devices" in the
  never-list; JS renderer updated with back-compat fallback),
  `weight-gallery-catalog.json` ×2 (label/role/note fields
  de-jargoned, `beats_claude` key → `beats_frontier`),
  `function-catalog.json` ("honest heuristic" → "heuristic"),
  `sdk-pack-MANIFEST.json` ("never RTX PRO 6000" dropped),
  `weight-playground.html` (renders "consumer GPU opt-in").

## Documented keepers (visible, deliberate)

- `docs/ATTENTION_FORWARD.md` + generated HTML: literal
  `control.sparkasm` **ATTN / ROPE macro names** — real code
  identifiers in a reference table, not status jargon.
- `docs/SPARKBC_MAKE.md` + generated HTML: `make
  spark-coder-train` / `make voice-easy` rows remain **only** on
  the make-target reference page (that page's subject is build
  targets; all feature/status copy uses product CLIs instead).
- `prefer_5090` JSON key name (invisible; renders "consumer GPU
  opt-in"). Generator flag `--5090` remains in
  `tools/spark-weights/cli.py` (tools lane); the public doc now
  shows only the `--cpu` example.

## Internal-doc occurrences (NOT edited — separate lane)

Non-rendering contributor/internal docs with banned patterns:

- `docs/ABSTAIN_HEADS.md` — 9 hits ("Honest scope", "honest
  metrics", "honest gate", "Dry/live coverage", …). NOTE: stale
  served page `website/docs/abstain-heads.html` (no longer in
  DOC_PAGES but still linked from 5 generated pages) **was**
  cleaned directly ("Honest gaps" → "Gaps").
- `docs/OS_DESIGN.md:3` — "## Honest scope".
- `docs/ENCRYPT_GATEWAY.md:53` — "honestly".
- `docs/ASK_LIVE.md:38` — "reserved voice GPU".
- `docs/MODEL_ANALYSIS.md:25` — "reserved … voice GPUs".
- `docs/docx/*.docx` — generated by `make docs-docx`, not
  website-served; inherit whatever the md sources carry.
- `tools/` source (e.g. `tools/spark-eval/claude_baseline.py`,
  `tools/spark-weights/cli.py` help text, `tools/spark-code/`) —
  code lanes, not public pages.
- `tools/md_to_doc_html.py:180` — dead `EVAL_HONESTY.md` legacy
  link-alias key (no md references it; internal redirect map, not
  injected content).

## Off-limits residual (flagged, not touched)

- `website/js/ide-shell.js:52,63` — two rendered **"Honest
  note:"** strings in the web IDE demo JS. File belongs to the
  `feat/decompile-no-mocks` lane per task scope. These two strings
  still render on `/docs/ide-shell.html` and need a follow-up in
  that lane.

## Verification

**Before (live site, pre-fix):** `https://sparklang.dev/docs/factory`
served the verbatim "Honesty bar" block incl. "Beat Claude — no",
"RTX PRO 6000", "voice-reserved".

**After regen (`make docs-html`; `make docs-check` OK — 45 pages,
41 nav hrefs):**

- Worktree `website/` grep (all html/js/json/svg/css): zero hits
  for `honesty|honest|claude|RTX|\b6000\b|reserved voice|voice
  GPU|MLP0|layer-0|planned stub|on tip|dry/live|frozen eval|
  multi-outer` except documented keepers (`prefer_5090` key,
  `control.sparkasm` macro row, `data.honesty` back-compat
  fallback in scoreboard JS) and the off-limits `ide-shell.js`.
- Served locally (`python3 -m http.server`): all edited pages 200;
  no empty sections / dangling headings (per-page check on
  factory, build-models, spark-coder, model-aspects, workflow,
  CHANGELOG, voice-easy, train-loop). CHANGELOG 0.6.40 empty
  heading removed.
- Sibling-genre grep ("capability bar", "status bar", "what's
  real"): zero hits.

**Live (post-deploy, `curl -sL https://sparklang.dev<url>`):**
CLEAN (zero banned hits) on `/`, `/workflow`, `/CHANGELOG`,
`/docs/factory`, `/docs/build-models`, `/docs/spark-coder`,
`/docs/model-aspects`, `/docs/voice-easy`, `/docs/attention-forward`,
`/docs/train-loop`, `/docs/abstain-heads`, `/learn/`,
`/weight-playground.html`. `/docs/factory` renders title + Map +
Quick start; SVG MIME `image/svg+xml` intact.

## Files changed (103 in commit `34ba94e`)

- docs/ source: 30 md files + 2 example JSONs + 9 SVGs
  (ADOPTION_BAR, AI_MODELS, ARCHITECTURE, ATTENTION_FORWARD,
  BUILD_MODELS, COMPILE, DECOMPILE, DECOMPILE_COMPETE, DIAGRAMS,
  EVAL, FACTORY, IDE, KNOWLEDGE, LANGUAGE, LSP, MODEL_ASPECTS,
  MODEL_TRAINING, PROGRAMMING_GUIDE, ROADMAP, SERVE, SPARKBC_MAKE,
  SPARK_BC, SPARK_BUILDER, SPARK_CODER, TRAIN_LOOP, VOICE,
  VOICE_ASK, VOICE_EASY, WEIGHT_GALLERY, knowledge/INFERENCE,
  knowledge/LLM_TRANSFORMERS, knowledge/MULTIMODAL,
  knowledge/SAFETY_LIMITS, research/LLM_DECOMPILE)
- generator: `tools/md_to_doc_html.py`
- website/: index, workflow, CHANGELOG, learn/index,
  weight-playground, css/site.css, js/decompile-scoreboard.js,
  data/decompile-scoreboard.json, data/function-catalog.json,
  downloads/sdk-pack-MANIFEST.json, docs/abstain-heads.html,
  docs/sdk-ide-download.html, docs/examples/*.json ×2 — plus 60
  regenerated `website/docs/*.html` / images.

## Git / CI / deploy record

- Branch: `fix/honesty-bar-purge` off `origin/main` (`38b35ec`).
- Commit `34ba94e` — 103 files, +527/−805.
- PR #66 — sparkbc CI success (run 34459734460, 10m40s).
- Merged `d2b4d63` (merge authority v3: in-session diff, green
  checks, this summary).
- Deployed via documented wrangler path from a detached worktree
  at `d2b4d63` (main tip also contained lanes #63/#64/#65 —
  deploying my branch tree would have regressed their
  404/sitemap/robots work; merge-tree grep confirmed no lane
  reintroduced banned content before upload).
- Live grep proof: see Verification above — all CLEAN.
