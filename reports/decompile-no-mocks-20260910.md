# decompile-no-mocks — 2026-09-10

Owner directive (Michael, 2026-09-10 03:27 CT): **"no static mocks no soft
spots"** — after a decompile audit found the toolchain REAL but with two
presentational soft spots, plus `"beats_claude"` markers in tool JSON output.

Worktree: `sparklang-wt-no-mocks` · branch `feat/decompile-no-mocks` ·
rebased onto origin/main `d2b4d63` before PR.

## What was mocked / declared

1. **Web IDE "Decompile" was a static demo shell.** `website/ide-web.html`
   shipped a Decompile button + dump pane explicitly labeled "Demo shell
   only" with canned "(demo)" content. No parsing happened.
2. **Parity badges were author-declared.**
   `website/docs/decompile-compete.html` carried a hand-painted static
   parity table (win/tie/loss/na vs OpenBin/Ghidra/IDA/Binja/
   LLM4Decompile), and `website/data/decompile-scoreboard.json` carried
   the same badges as constants — only the numeric rows were measured.
3. **`beats_claude` field** was emitted by ~20 tools/libraries as a
   constant `false` marker (voice_ask, gui core, analyze, spark-voice,
   spark-code, spark-eval, spark_kit, package_helpers_k, spark-check-env,
   weights, weight_gallery, voice_easy, spark_coder, senses) and embedded
   in checked-in JSON data files (models/*, scale configs, weight-gallery
   catalogs).

## What is real now

### Soft spot 1 — real client-side decompiler (static-site safe)

- **`website/js/sparkbc.js`** (new): full client-side port of
  `python/sparklang/model_lab/bc_dump.py` (558-line struct-level decoder).
  u16/u32 little-endian reads, OP_ARITY/OP_NAME tables, string/const
  pools, code decode, xrefs, analysis, Python-repr emulation, xxd
  formatting, sha256 via `crypto.subtle` (browser + node ≥19), and a
  safetensors header parser (u64le length + JSON). UMD export
  (`module.exports` + `window.SparkBC`) so the *same file* is served on
  the page and driven under node for the parity gate.
- **`website/ide-web.html` + `website/js/ide-web.js`** (rewritten): every
  pane computes from real parsed bytes —
  (a) **Open .sparkbc…** file upload parses the user's real file;
  (b) **Load bundled fixture** fetches the real compiled
  `website/docs/examples/spark-train-step.sparkbc` (and its `.spark`
  source, new static asset) and parses it live — the fixture auto-loads
  on page open, so the dump pane is never empty shell text;
  (c) Decompile (ops table), Dump (full text), Weights (safetensors
  tensor table), Report (markdown download), and Ask (factual answers
  from parsed structures) all render only parser-computed output.
- **Compile button removed** — a static Cloudflare Pages site cannot run
  the Spark compiler client-side; per directive, buttons that cannot be
  real are removed, not demoed. Zero "demo" / "mock" labels remain
  (grep proof below; the one `placeholder=` hit is an HTML input hint
  attribute, not product content).

### Parser parity proof (JS ≡ Python, byte-for-byte)

- **`tools/spark-bc-dump/js_parity.js`** (new): node bridge that loads
  the exact served `website/js/sparkbc.js` and prints `{dump, analysis}`.
- **`tools/spark-bc-dump/test_js_parity.py`** (new): runs `bc_dump.py`
  and the node bridge on all three published fixtures
  (`spark-train-step`, `spark-builder`, `spark-self` `.sparkbc`) and
  asserts **byte-identical dump text** and identical analysis dicts;
  bad-magic input fails loud on both sides. Wired as
  `make test-js-parity` and as a CI step in `.github/workflows/sparkbc.yml`.
- Result: `ok test_js_parity (3 fixtures)` — local and CI.

### Soft spot 2 — every badge computed from measured probes

- **`tools/spark-bc-dump/decompile_bench.py`** rewritten so
  `_parity_matrix()` computes each cell:
  - Spark cells: fixture decode metrics (symbols/xrefs/sections on real
    bytes), round-trip % from `roundtrip.run_all()`, the
    `spark-binary-probe --elf ./spark` local probe, and the sample
    analysis-project write. Multi-format ELF/PE is an honest measured
    **loss** (probe lists hdr+sections only — not Ghidra-class).
  - Competitor cells: byte-level probes where scripted (objdump:
    `objdump -d` on a real .sparkbc → measured `na`; `objdump -h ./spark`
    → measured `win`). Tools absent from the box, or with no scripted
    byte-level probe, render **"not probed"** — never a declared badge.
- Regenerated `website/data/decompile-scoreboard.json` (+ `docs/examples`
  and `website/docs/examples` mirrors) via `make decompile-bench`.
- **`website/js/decompile-scoreboard.js`** rewritten: renders the
  dashed-gray "not probed" badge, the objdump column, and a not-probed
  summary count.
- **`website/docs/decompile-compete.html`**: hand-painted static parity
  table removed; the "Feature parity matrix" section is now legend +
  pointer to the JS-rendered measured scoreboard (the only matrix on the
  page). Remaining content tables (beat-axes, not-claimed) are prose,
  not badges.
- **`test_decompile_compete.py`** gained two gates:
  `test_parity_badges_computed_not_declared` (flip measured inputs →
  badges flip; absent tools → all cells "not probed"; no scripted ghidra
  probe → always "not probed") and
  `test_scoreboard_parity_cells_are_probe_derived` (live scoreboard:
  every cell ∈ {win, tie, loss, na, not probed}; non-present tools are
  all-"not probed").

### Scoreboard diff summary (declared → computed)

- Shape: 11 hand-written rows → 7 measured categories × 7 tools
  (spark, objdump, openbin, ghidra, ida, binja, llm4decompile).
- Before: competitor badges were constants (e.g. ghidra `na` on every
  row). After: **39 "not probed" cells**; spark = 6 win + 1 measured
  loss (ELF/PE); objdump = 1 measured win (ELF) + 2 measured na
  (SPARK_BC); openbin/ghidra/ida/binja/llm4decompile = 7/7 not probed.
- New `honesty` string states the computation rule; `summary_counts`
  includes `not probed`.

### beats_claude sweep

- Field removed from every emitter (full list above under "What was
  mocked"). Tests, Makefile inline asserts, and `run_e2e_gate.sh` now
  assert **absence** (`assert "beats_claude" not in …`);
  `apply_step.py` exits 2 if the field ever returns.
- JSON data files stripped: `models/spark-coder/{arch,checkpoint,
  factory_step_checkpoint}.json`, `models/spark-voice-easy/{arch,
  checkpoint}.json`, `examples/fixtures/{coder,train}/scale_config.json`,
  both `weight-gallery-catalog.json` copies.
- `models/spark-voice-easy/weights.safetensors` regenerated via
  `make test-voice-easy`: tensor bytes **bit-identical** to origin/main;
  only the `__metadata__.beats_claude` key is gone (verified by header
  diff — 23-byte shrink, no value changes).
- `tools/scrub_public_claims_leaks.py`: stale comments claiming the
  field "stays in eval JSON" corrected; prose-scrub patterns retained
  for historical docs.
- Grep proof: `grep -rl beats_claude --include="*.json" .` → **0**;
  remaining code references are absence-asserts, the apply_step
  rejection guard, and prose scrubbers only.

## Rebase note (both intents kept)

Main landed #64 (real-coder), #65 (site-infra), #66 (honesty-bar-purge)
mid-work. 11 conflicts resolved: spark_coder + spark-code taken from
main (already beats_claude-free, real-coder rewrite intact — including
their `assertNotIn` tests and `payload.pop` guard); scoreboard JSON/JS
and IDE files taken from this branch; weight-gallery catalogs merged
(their scrubbed prose, no `beats_*` key); Makefile keeps both their
probe targets (test-pe-probe, test-decompile-assist, probe-pe,
probe-assist) and `test-js-parity`.

## Gate results (all on the rebased tree)

| Gate | Result |
| --- | --- |
| `make test-sparkbc` | PASS |
| `make test-sparkbc-e2e` | PASS ARTIFACT (checkpoint loss 2.1967→1.7018) |
| `make test-decompile-compete` | ok (incl. 2 new computed-badge gates) |
| `make decompile-roundtrip` | PASS (100% on published fixtures) |
| `make decompile-bench` | PASS (scoreboard regenerated) |
| `make test-js-parity` | ok (3 fixtures, byte-identical) |
| `test_gui_pack.py` | 11 tests OK |
| `make test-spark-analyze` / `tools-test` | OK / IDENTICAL |
| `make test-spark-eval` | OK |
| `make test-spark-coder` | OK (main's rewritten suite) |
| `make test-spark-ask` | OK |
| `make test-voice-easy` | OK |
| `make test-weights-play` | play_ok |
| `make test-senses` | OK |
| `make test-sdk-pack` | OK |
| `test_weight_gallery` | 10 tests OK |
| `make spark-sgd-proof` / `spark-sgd-proof-scale` | PASS (edited asserts verified live) |
| `make test-pe-probe` / `test-decompile-assist` | ok (main's new targets, merged Makefile) |

### GUI smoke — real headed-under-xvfb (recorded)

`xvfb-run` exists on the box, so a real headed smoke ran (not
headless-only): `xvfb-run -a -s "-screen 0 1400x900x24"` +
`PYTHONPATH=tools:python python3 -m spark_bc_gui`. On display :101 the
window "Spark IDE — browse · compile · ask · weights" mapped at
1280x800 (verified via `xdotool search` + `xwininfo`), root screenshot
captured (`import -window root`) showing the full three-pane UI, process
alive after checks, no traceback. **GUI SMOKE PASS.**

## PR + merge + deploy state

- PR: https://github.com/sparklang-dev/sparklang/pull/69 —
  "decompile: real client-side decompiler + measured parity badges — no
  mocks"
- CI: `sparkbc` workflow **pass** (10m36s) — includes the new
  `test-js-parity` step.
- Merged: 2026-09-10T09:57:03Z (merge authority v3: checks green,
  in-session diff, this report is the summary echo).
- Deploy: site is Cloudflare Pages (auto-build from `main`; repo has no
  Pages workflow — only `sparkbc.yml`). The merge push triggered the
  Pages build; the deploy id is not observable from this box via `gh`
  (Cloudflare-side). No credential hunt attempted.

## Grep proofs (final state)

- Demo/mock UI: `grep -ci "demo\|mock\|placeholder\|lorem"
  website/ide-web.html website/js/ide-web.js website/js/sparkbc.js` →
  only one hit, an HTML `placeholder=` input hint. No "(demo)",
  "Demo shell", or mock content anywhere.
- Declared badges: static parity table removed from
  `decompile-compete.html` (only `doc__table` instances left are the
  prose beat-axes and not-claimed tables); published scoreboard has 39
  computed "not probed" cells and zero author-declared competitor
  badges.
- `beats_claude`: zero occurrences in any JSON; code retains only
  absence-assertions and the rejection guard.
