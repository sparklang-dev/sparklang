# Site copy refresh deck — 2026-09-10

**Owner direction (Michael, 2026-09-10 ~03:15 CT):** the current hero is
"dumb" — banned competitor comparison in the hero, bragging about being
"tiny", insider snark ("LoRA theater"), "dry-run fixtures in CI" sold as a
feature, walls of internal codenames instead of benefits, and
apology-as-positioning. Also standing orders from tonight: get rid of the
Claude language; no tiny-models-and-weights framing — real ones, the best;
make everything about sparklang.dev better.

**Scope of this deck:** replacement copy for every public page. This deck
changes no HTML. A later application pass edits `website/*.html` (and the
docs sources that generate `website/docs/*`) using the OLD → NEW pairs
below as find-and-verify.

**Applies after:** the voice-real-weights branch lands (voice-easy is now
fetch-open-weights → measured eval, no toy training). Voice copy below is
written against that reality.

---

## Voice and tone

Plain, direct, confident, builder-to-builder. Short sentences. Say the
thing, show the proof command, stop. No hype adjectives, no exclamation
points, no "revolutionary". Every capability sentence names something the
repo does today; where useful, point at the command that proves it.

## Banned list (explicit)

- **"Claude"** — anywhere on the public site, any context.
- **"beats"** — no "beats X", no "win claim", no "competitive AI win".
- **"theater"** — e.g. "LoRA theater". No insider snark at all.
- **"tiny and honest"** — and the whole size-apology genre. Do not sell
  smallness; do not apologize for it either. Describe what things do.
- **"dry-run fixtures" as a selling point** — the user benefit is
  *runs offline, nothing leaves your machine*. Fixtures are an
  implementation detail for docs, not a headline.
- **Internal env-var / codename walls in marketing copy** —
  `SPARK_TRAIN_URL`, `spark_distill_cpu`, `spark_pref_pack`, etc. belong
  in docs and terminal blocks, not in hero or section prose. In prose,
  say the plain-English thing ("point Spark at your own training
  service", "five reference trainers that run on CPU").
- **"not X" positioning** — no "not a vendor SaaS", "not an OpenBin
  clone", "not a claim to beat frontier models", "no fake beats all".
  Copy stands on what the product does.
- **No invented features, no inflated claims, no fake testimonials, no
  "production-grade"** without evidence.

## Truth constraints (hard)

Every capability sentence below maps to something the repo does:

| Claim used in copy | Proof in repo |
| --- | --- |
| Compiles to a bytecode you can dump and inspect | `./spark-bootstrap --compile …` → SPARK_BC; `tools/spark-bc-dump/dump.py`; `spark-bc-gui` |
| Runs offline, no API keys | `./spark --dry-run examples/train_eval.spark` (exit 0/1) |
| Train, poll, assert in one file | `model train` / `model status` / `expect contains … fixture` |
| Five reference trainers on CPU | `tools/spark-train-ref`: distill, preference pack, playbook fit, FAQ index, reply pack — live captures in `docs/examples/live-train-*.txt` |
| Live training against your own service | `backend "http"` trainer contract, `docs/model-training.html` |
| Serve locally | `docs/SERVE.md`, helpers / shadows |
| Real voice: open speech models, self-hosted, offline after one download | `tools/spark-voice/fetch_models.py` (pinned sha256; Whisper MIT / CT2 repack, Kokoro Apache-2.0); `stt_real.py` / `tts_real.py` force offline mode |
| Measured voice eval, real audio | `eval_real.py`: WER/CER on held-out LJSpeech; TTS→STT roundtrip WER |
| Grounded answers abstain when wrong | `./spark-ground` — evidence miss → exit 2 |
| IDE | `spark-bc-gui` desktop, `ide-web.html` shell, LSP |
| Open source, MIT | `website/LICENSE.txt`, github.com/sparklang-dev/sparklang |

Allowed framing: "verifiable", "every claim gated by a test you can
rerun" — phrased as the user's benefit (you can check us), never as CI
trivia.

---

# 1. `website/index.html`

## 1.1 Hero

**OLD**

> Eyebrow: SparkLang
>
> # From .spark to SPARK_BC — then prove it
>
> One reviewable language surface for compile → dump → train → serve →
> share. Dry-run fixtures in CI. Owned `spark-coder` stays tiny and
> honest — , not "competitive AI win""
>
> Offline-first: `./spark --dry-run`. Live jobs hit `SPARK_TRAIN_URL`.
> Five CPU reference methods: `spark_distill_cpu`, `spark_pref_pack`,
> `spark_playbook_fit`, `spark_faq_index`, `spark_reply_pack`.
>
> CTAs: Download Spark · The Spark loop · Playground

**NEW**

> Eyebrow: SparkLang
>
> # Write it. Compile it. Prove it.
>
> SparkLang is an open language for AI work. Programs compile to a
> bytecode you can dump and inspect line by line. Training, serving, and
> real voice — ears and speech — are built in. It runs offline and
> self-hosted, with no API keys required.
>
> Every capability on this site ships with a command you can rerun
> yourself. MIT licensed. Source on GitHub.
>
> CTAs: **Download Spark** (primary, `/downloads.html`) ·
> **See the workflow** (secondary, `/workflow.html`) ·
> **Try in the browser** (ghost, `/playground.html`)

**Meta description (head) — OLD:** "SparkLang: reviewable .spark programs
through SPARK_BC — compile, dump/inspect, train or step with owned tiny
spark-coder, serve helpers, share on Pages. Five CPU train methods — not
LoRA. Dry-run CI."

**NEW:** "SparkLang is an open language for AI work: compile to a
verifiable bytecode, train real models, serve locally, and speak and
listen with built-in voice. Runs offline and self-hosted — no API keys
required. MIT."

**Meta keywords — NEW:** "SparkLang, Spark programming language, .spark,
verifiable bytecode, offline AI, self-hosted voice, model training"

## 1.2 Loop strip (nav element under hero)

Structure stays (01–05, same anchors). Replace hint text only:

| Step | OLD hint | NEW hint |
| --- | --- | --- |
| 01 Compile | `.spark → SPARK_BC` | `source → bytecode` |
| 02 Inspect | `dump · spark-bc-gui` | `dump and verify locally` |
| 03 Train | `step · spark-coder` | `jobs you can rerun` |
| 04 Serve | `helpers · shadows` | `from your own machine` |
| 05 Share | `docs · Pages` | `docs and examples` |

## 1.3 Trust strip

**OLD:** "SparkLang at sparklang.dev · MIT license · Source on GitHub ·
v0.6.56 · Changelog · Installers on this site"

**NEW:** keep all items; insert one more fact:
"**Runs offline — no API keys**". (Also unify the version string — see
Application notes.)

## 1.4 Section: "Why a language?"

Keep title. Section lede:

**OLD:** "Library glue scatters prompts, training scripts, and eval
harnesses across repos. A `.spark` program is one reviewable surface —
same file for dry-run CI and live ops."

**NEW:** "AI work tends to sprawl: a prompt in one repo, a training
script in another, an eval harness in CI. A Spark program puts the whole
job in one file you can read top to bottom — and rerun exactly, on your
machine, with no accounts."

Compare cards — keep both code blocks (they are real and contain no
competitor names). Retitle:

- OLD "Typical Python SDK soup" → NEW "**The usual sprawl**"
- OLD "One .spark program" → NEW "**One Spark program**"

## 1.5 Section: "The wedge"

**NEW title:** "What Spark does for you"

**NEW section intro:** "Three things a single Spark file gives you that
scattered scripts do not."

Card 1 — OLD title "Dry-run by default"; body: "`./spark --dry-run` uses
offline fixtures — no keys, no network. Pass `--live` only when you want
real calls."

NEW title "**Offline by default**". NEW body: "Every example runs with
no network and no keys — nothing leaves your machine. Go live only when
you point Spark at your own services." Keep the command line
(`./spark --dry-run examples/model_train.spark`).

Card 2 — OLD title "Train backends wired"; body is a wall of
`SPARK_TRAIN_URL` / `POST …/jobs` / five `spark_*` method codenames /
"not LoRA".

NEW title "**Real training, on your hardware**". NEW body: "Submit a
training job from the same file, poll its status, and bind the
artifacts. Spark ships five reference trainers that run on CPU —
distillation, preference packing, playbook fitting, FAQ indexing, and
reply packing — so the full loop works on a laptop. When you outgrow
them, point Spark at your own training service over HTTP. Proof:
live-train-capture.txt, live-train-methods-capture.txt." (Keep both
capture links and the Trainer HTTP contract docs link; keep the
two-line code block.)

Card 3 — OLD title "Eval in the same file"; body: "After train, assert
bound job and status fields with `expect contains … fixture` (exit 0/1)
— gate of *this* job, not unrelated gateway aliases."

NEW title "**Pass/fail in the same file**". NEW body: "After a run,
assert on the actual output. Expectations exit 0 or 1 — the gate judges
this run, on this machine, and you can rerun it." (Keep the code block.)

## 1.6 Section: "Train → status → expect"

Keep title and the 3-step pipeline (Train / Status / Expect) and the
terminal block.

Section lede — OLD: "Dry-run writes fixture artifact paths (no GPU).
Live POSTs to the trainer at `SPARK_TRAIN_URL` (`backend "http"`), or an
allowlisted `local-yield` unit."

NEW: "The whole training loop is three lines: submit a job, poll its
status, assert the result. It runs offline out of the box. When you are
ready for real training, point Spark at your training service — the same
file goes live."

Trailing prose — OLD: "Fail path: `examples/train_eval_fail.spark`
(exit 1). Live HTTP proof (five CPU methods, via) `./spark --live` /
`./spark-train-http --method`): live-train-methods-capture.txt. …"

NEW: "Fail path: `examples/train_eval_fail.spark` exits 1. Live proof
against the reference trainers: live-train-methods-capture.txt." (Keep
the three trailing doc links.)

## 1.7 Section: "Also on tip"

**NEW title:** "Also in the box"

Section lede — OLD: "Beyond the train → status → expect wedge: local
`spark-analyze`, grounded asks with `./spark-ground`, voice ask / voice
easy, the three-pane IDE (`spark-bc-gui`), weight gallery, and decompile
scoreboard. Details live in the factory hub, language reference, and
what's shipping today."

NEW: "Beyond the training loop: grounded answers that abstain instead of
guessing, real voice — recognition and synthesis on your machine — a
three-pane IDE, a weight gallery, and a measured decompile scoreboard."
(Keep the three trailing links.)

Cards:

- **Grounding** — OLD body: "`./spark-ground` — verify-before-speak;
  wrong fixture → abstain."
  NEW: "Ask questions with evidence attached. When the evidence does not
  support the answer, Spark abstains instead of guessing."
- **IDE functions** — OLD body: "Browse · dump · ask · weights play ·
  helpers — local panes."
  NEW: "Compile, decompile, dump, ask, and inspect weights from one
  local workbench."
- **Decompile bench** — OLD body: "Measured scoreboard (wins / ties /
  losses / N/A) — no fake "beats all.""
  NEW: "A published scoreboard of decompile results — wins, ties, and
  losses, measured and rerunnable."
- **Weight gallery** — OLD body: "Catalog stub weights; inspect, diff,
  play forward on CPU / 5090."
  NEW: "Inspect, diff, and run model weights forward — on CPU or your
  GPU."

## 1.8 Section: "Learn Spark"

Section lede — OLD: "Follow the trail: install → first dry-run →
train→status→expect → gate a job. Field concepts live in the AI
knowledge hive."

NEW: "Install, run your first program offline, then gate a real training
job — the docs walk the same loop this site describes. Deeper background
lives in the knowledge hive."

Cards (titles/links stay; replace bodies):

- **AI knowledge hive** — OLD: "Transformers, training, inference,
  agents, evaluation — engineer explainers with diagrams. Not a Claude
  win claim."
  NEW: "Transformers, training, inference, agents, evaluation —
  engineer-level explainers with diagrams."
- **Getting Started** — OLD: "Install the runtime and verify with
  `./spark --dry-run`."
  NEW: "Install the runtime and run your first program offline in
  minutes."
- **Your First Program** — OLD: "A minimal train → status → expect loop
  you can dry-run in CI."
  NEW: "A minimal train, status, expect loop that runs offline from the
  first minute."
- **AI in 5 Minutes** — OLD: "Orchestrate jobs, expect gates, classify,
  extract — the train→status→expect primitives."
  NEW: "Orchestrate jobs, gate results, classify and extract — the core
  primitives in five minutes."
- **Build a Model** — OLD: "Submit a dry-run train job, poll status,
  then expect pass/fail."
  NEW: "Submit a training job, poll its status, and assert the outcome —
  pass or fail."
- **Factory docs hub** — OLD: "Engineer map: compile, decompile,
  opcodes, TRAIN/STEP, train loop, architecture, tokenizer, serve, eval,
  make, CI/Pages, plus diagrams and model aspects (ears / eyes /
  speaking / behaviors) and owned spark-coder. Honest —"
  NEW: "The engineer's map: compile, decompile, opcodes, training,
  serving, evaluation, diagrams, model aspects — ears, eyes, speaking,
  behaviors — and the in-repo Spark coder model."
- **Builder — SPARK_BC factory** — OLD: "Spark compiles Spark to
  SPARK_BC (`TRAIN` / `STEP` / `TRAIN_STATUS`), dumps hex, emits
  Spark-created init weights. Dry ≠ trained. GAS `--compile` wraps
  bootstrap."
  NEW: "Spark compiles Spark. The builder emits bytecode with training
  opcodes, dumps it to hex for inspection, and writes initial weights
  you can train from."

## 1.9 Section: "Try it"

Keep both terminal blocks verbatim (commands are docs, not marketing).
First comment line already says the right thing ("no network, no API
key"). In the second block, replace the comment
"# Optional live submit — your trainer at SPARK_TRAIN_URL" with
"# Go live against your own trainer when you're ready". Keep the
`export SPARK_TRAIN_URL=…` line itself — it is the real command.

Trailing prose stays: "See programming guide and language reference."

---

# 2. `website/about.html`

## 2.1 Meta description

OLD: "SparkLang — reviewable .spark programs with five CPU train methods
(distill, preference pack, playbook fit, FAQ index, reply pack) — not
LoRA — then status→expect with dry-run CI. MIT. Contact
hello@sparklang.dev."

NEW: "SparkLang is the home of the Spark programming language — an open,
MIT-licensed language and runtime for AI work. Offline by default, no
API keys. Contact hello@sparklang.dev."

## 2.2 Intro paragraph

OLD: "**SparkLang** is the public name for the **Spark programming
language** at sparklang.dev. A language beats another Python SDK because
one reviewable `.spark` file covers train → eval → ship, with dry-run
fixtures for CI without API keys."

NEW: "**SparkLang** is the home of the **Spark programming language** —
an open, MIT-licensed language and runtime for AI work. One Spark file
covers the whole job: train, evaluate, serve, and ship. It runs offline
by default, so you can read, run, and verify everything before anything
leaves your machine."

## 2.3 "What it is" list

OLD:

- A **language + runtime** for plain `.spark` files.
- **Dry-run / offline by default** — no API keys and no network for
  learning and CI.
- **Real training** via `model train` / `model build` (jobs + status).
  `model plan` is plan-only markdown.
- Optional live `ask` against any OpenAI-compatible gateway via
  `AI_GATEWAY_URL` and `./spark --live`.

NEW:

- A **language and runtime** for plain-text `.spark` files — readable,
  diffable, reviewable.
- **Offline by default** — no API keys, no network, nothing leaves your
  machine until you say so.
- **Real training** — submit jobs, poll status, and assert results from
  the same file.
- **Real voice** — speech recognition and synthesis from best-in-class
  open models, self-hosted, offline after a one-time download.
- **Optional live asks** — point Spark at any OpenAI-compatible gateway
  you choose.

## 2.4 "Name note" section

Keep as-is. Factual disambiguation (Apache Spark, AdaCore SPARK), not
positioning.

## 2.5 "Core vs optional" table

OLD Core row: "Language, dry-run fixtures, model train/build/status,
ask/eval helpers, playbooks, IDE language ops"

NEW Core row: "Language and compiler, offline runs, model
train/build/status, ask and eval helpers, playbooks, IDE"

OLD Optional row: "Live ask/embed; voice (gated); browser / capture"

NEW Optional row: "Live gateway asks and embeddings; voice models
(one-time download); browser and capture helpers"

## 2.6 "Trust" section

Keep all items. Fix the version string (page says 0.6.3, index says
v0.6.56 — unify; see Application notes).

---

# 3. `website/workflow.html`

## 3.1 Meta description

OLD: "SparkLang five-step loop: compile SPARK_BC, dump/inspect locally,
train or step with owned spark-coder, serve helpers/shadows, share docs
on Pages. Original Spark design."

NEW: "The Spark loop: compile to a verifiable bytecode, inspect it
locally, train real models, serve from your machine, and share what you
built."

## 3.2 Hero

Title stays: "Compile. Inspect. Train. Serve. Share." (It is good.)

Lede — OLD: "One Spark-native path from a reviewable `.spark` file to
`SPARK_BC`, local dump, owned tiny coder steps, helpers on the wire, and
docs on Pages — CLI first, GUI where it helps."

NEW: "One path from a readable Spark file to a bytecode you can inspect,
models you trained yourself, and services running on your own hardware.
Command line first, graphical tools where they help."

Figure caption — OLD: "Original Spark diagram — SPARK_BC orchestration
bytecode, not imported neural weights."

NEW: "The Spark loop — programs compile to orchestration bytecode you
can inspect at every step."

## 3.3 Section: "Five steps, Spark tools"

Section lede — OLD: "Inspired by clear CLI→inspect→publish loops
elsewhere — rebuilt around **our** binaries, dumps, and honest model
claims. No third-party branding on this page."

NEW: "Five steps. Each has a tool you can run and an output you can
check."

### Step 01 — Compile

Body — OLD: "Author a `.spark` program, then
`./spark-bootstrap --compile` (or open an existing pack). Output is
Spark's own `SPARK_BC` — orchestration ops like `TRAIN` / `STEP`, not a
weight dump."

NEW: "Author a Spark program and compile it. The output is Spark's own
bytecode — orchestration operations like train and step, written out
where you can see them." (Keep links and the command block.)

### Step 02 — Inspect

Body — OLD: "Primary SoT: `tools/spark-bc-dump/dump.py` — hex, header,
mnemonics. One-shot project loop: `./helpers/spark-analyze` → local
`out/analyze/<name>/` (dump, ops list, REPORT stub; optional `--serve` /
`--ask`). Optional `spark-bc-gui` for a readable pane. Deterministic
inspect first; LLM research is a separate, cited lane."

NEW: "Dump the bytecode locally — hex, headers, mnemonics — or open it
in the graphical inspector. One command builds a full analysis folder on
your disk: dump, opcode list, report stub. Nothing is uploaded
anywhere." (Keep links and command blocks.)

SVG mock caption — OLD: "IDE-ish panes mock built from Spark dump
vocabulary (SPBC magic, TRAIN/STEP) — clearly Spark, not pseudo-C
malware reverse engineering."

NEW: "Inspector panes built from real Spark dump vocabulary."

Voice-ask subsection — OLD: "After inspect, ask in text or speech —
ears (STT) → dump context + owned TinyCoder → speaking (TTS). Local
only; **no** OpenBin login. TinyCoder is tiny: dump facts stay SoT;
open-ended RE answers carry an status note."

NEW: "Then ask questions about what you found — by text or by voice.
Recognition and synthesis run locally. Answers come from the decoded
dump first; when the evidence runs out, Spark says so." (Keep links and
command blocks.)

### Step 03 — Train

Body — OLD: "Run `model train` → `model status` → `expect` in one file.
Owned `spark-coder` is a **tiny** capability — useful for Spark factory
loops, not a claim to beat frontier models."

NEW: "Run train, status, and expect in one file. Spark ships reference
trainers that run on CPU, plus an in-repo coding model you can train,
dump, and inspect end to end — every weight on your disk."

Voice paragraph — OLD: "**Train voice / STT / TTS in 3 steps** — Voice
easy (`make voice-easy`): tiny CI default or `--scale large` on an RTX
5090 (or CPU). Owned heads —"

NEW: "**Real voice in 3 steps** — fetch the open speech models once, run
the measured eval, check the status. Recognition and synthesis are
best-in-class open weights, self-hosted, offline after the download.
Details: Voice easy."

"Honest bar" note — OLD: "Honest bar: CPU reference methods and owned
tiny coder / voice heads. Does **not** publish a competitive AI win
claim. or replace a vendor TTS stack overnight."

NEW (replace the whole note): "Proof: the voice eval reports real
word-error rates on held-out speech. The commands are on the voice
pages."

### Step 04 — Serve

Body — OLD: "Local HTTP surfaces for helpers and shadows — wire a
trainer at `SPARK_TRAIN_URL`, probe serve APIs, keep dry-run as the
default gate."

NEW: "Serve from your own machine: local HTTP surfaces for helpers and
isolated rebuilds, with your training service wired in when you are
ready. Offline stays the default."

### Step 05 — Share

Body — OLD: "Ship factory docs and examples on sparklang.dev
(Cloudflare Pages). Share packs and captures from the gallery below —
Spark-appropriate examples, not a malware community feed."

NEW: "Publish docs, examples, and captures. This site is built the same
way — and everything in the gallery below is a program you can run
yourself."

## 3.4 Examples gallery

Cards (titles/links stay; replace bodies where listed):

- **train_eval.spark** — OLD: "Minimal CI gate with fixture artifacts."
  NEW: "The minimal offline gate: train, status, expect."
- **spark-coder** — OLD: "Tiny owned coding model notes — capability,
  not hype."
  NEW: "The in-repo coding model — architecture, training, and weights
  you can inspect."
- Others (SPARK_BC dump capture, Playground, Factory diagrams,
  spark_train_step) are factual; keep.

## 3.5 "Start here" section

Keep as-is (three CTAs, no copy problems).

---

# 4. `website/downloads.html`

## 4.1 Meta description

OLD: "Download Spark AI-first runtime installers for Linux, macOS, and
Windows."

NEW: "Download Spark for Linux, macOS, and Windows — graphical
installers, offline by default, no API keys."

## 4.2 Intro paragraph

OLD: "**SparkLang** is a language and runtime for plain `.spark` files:
`ask`, `classify`, `extract`, `pipeline`, `review`, `model` train (real
jobs), and optional `voice`. Dry-run offline with fixtures is the
default; live `ask` via `AI_GATEWAY_URL` is optional (`--live`)."

NEW: "**Spark** is a language and runtime for AI work: ask, classify,
extract, pipeline, review, train real models, and listen and speak with
built-in voice. Every install runs offline out of the box — no accounts,
no API keys."

## 4.3 Rest of page

Keep as-is. The installer tables, quick-start commands, verify block,
and build-from-source section are factual instructions, not marketing
prose. (Application pass: the hardcoded `0.6.0` version placeholders are
filled from the manifest at runtime — leave them.)

---

# 5. `website/ide-web.html`

## 5.1 Meta description

OLD: "Static demo of Spark's dense IDE shell: rail · editor/dump ·
tools. Desktop spark-bc-gui uses the same design tokens."

NEW: "A look at the Spark IDE shell: files, source, bytecode dump, and
tools in one dense local workbench."

## 5.2 Rail note

OLD: "Demo shell only — wire real actions via desktop `spark-bc-gui` /
IDE functions lane. Tokens shared with the site."

NEW: "This page is a static preview. The desktop IDE runs the real
compile, decompile, dump, and ask actions — locally, on your machine."

## 5.3 Scope note (tools rail)

OLD: "Owned tiny models only. Prefer CPU or a consumer GPU for train."

NEW: "Runs on your machine. CPU is enough; a consumer GPU speeds up
training."

## 5.4 Status bar

OLD: "Ready · theme tokens polish0909 · dense IDE chrome"

NEW: "Ready · local · offline"

---

# 6. Voice pages (`website/docs/voice*.html`; sources in `docs/`)

These reflect tonight's truth: voice-easy is now real open weights
(Whisper-class recognition, Kokoro-class synthesis), fetched once with
pinned checksums, then fully offline; the eval reports real WER/CER on
held-out LJSpeech audio. Do not claim frontier parity. Do not say
"owned weights trained by us" — they are open weights (MIT / Apache-2.0);
the truthful framing is "open weights, fetched once, verified, then
offline".

## 6.1 `voice-easy.html` (source `docs/VOICE_EASY.md`) — largest rewrite

Title — OLD: "Voice easy — train STT / TTS in 3 steps"
NEW: "**Voice easy — real ears and voice in 3 steps**"

Intro — OLD: "Piece-of-cake path for **owned** Spark voice-related heads
we write and train in this repo. … Owned Spark STT/TTS heads trained in
this repo — not a vendor TTS SaaS. Prefer CPU or a consumer GPU for
optional train."

NEW: "The fastest path to real voice in Spark. Recognition and synthesis
use best-in-class open speech models — Whisper-class ears, Kokoro-class
voice — self-hosted on your machine. The weights are open (MIT and
Apache-2.0), fetched once with pinned checksums, and then everything
runs offline. No API keys. No account. No audio leaves your machine."

3 steps — OLD:

```bash
# 1) Env check (no secrets)
./spark-voice env --dry

# 2) Tiny happy path (CI / laptop) — fixtures → train → prove
make voice-easy

# 3) Status
./spark-voice status
```

NEW:

```bash
# 1) Fetch the open models once (pinned checksums)
./spark-voice fetch

# 2) Run the measured eval — real audio, real error rates
./spark-voice easy --scale large

# 3) Status
./spark-voice status
```

Outputs — OLD: "models/spark-voice-easy/weights.safetensors …
out/voice_easy/fixtures/ — owned tone WAVs + phrases …
out/voice_easy/roundtrip/ — TTS dry WAVs + roundtrip.json"

NEW: "What you get:

- **Speech-to-text measured on real audio** — held-out LJSpeech clips
  transcribed and scored with word and character error rates against the
  published transcripts.
- **Text-to-speech you can hear** — natural speech WAVs, verified by
  transcribing the synthesis back and scoring the roundtrip. A real
  intelligibility number, not a file-size check.
- **Every model file verified** against a pinned sha256 before it runs."

Scales table — OLD: "tiny (default) dim 16, ~12 steps, CPU fine; CI ·
large (opt-in) dim 256, ~80 steps, Prefer 5090; ~2 GiB VRAM hint"

NEW:

| Scale | What runs | Hardware |
| --- | --- | --- |
| **tiny** | Whisper tiny — CI smoke check | CPU |
| **large** | Whisper large-v3-turbo recognition + Kokoro synthesis — the measured lane | CPU by default; a consumer GPU speeds it up |

"Large ≠ production vendor quality…" paragraph — DELETE (apology
genre). Replace with: "The large lane is the real measurement: error
rates on held-out speech, printed as numbers."

"Fail closed (reserved voice GPU)" section — keep (operational fact,
docs-appropriate), but drop it from any marketing context.

Flags table — keep, minus rows that only describe the deleted training
path.

"Reuse ears / speaking" — OLD diagram text: "ears (fixtures /
spark-stt-tts) → voice-easy STT head (classify phrases) → brain … →
voice-easy TTS head (PCM params) → speaking (roundtrip WAV …)"

NEW: "The language `listen` / `speak` surface and the voice-easy models
are the same ears and voice:

```text
ears (Whisper-class recognition, local)
 → your Spark program (dump facts, grounded answers)
 → voice (Kokoro-class synthesis, local)
```"

"External STT / TTS sidecars" gates table — keep (factual config docs).

Scope table — OLD rows: "Owned STT/TTS heads we train — yes (tiny +
large) · CI dry green — yes · Prefer RTX 5090 (or CPU) for GPU train —
yes · Vendor mega-TTS overnight — Out of scope · Marketing win banners —
Out of scope"

NEW rows:

| Claim | Status |
| --- | --- |
| Open weights (Whisper MIT / Kokoro Apache-2.0), fetched once | yes |
| Offline after the fetch — no network in any eval path | yes |
| Measured WER/CER on held-out real speech | yes |
| Marketing superlatives | none — the eval numbers are the claim |

## 6.2 `voice-ask.html` (source `docs/VOICE_ASK.md`)

Intro — OLD: "Speak to a **local** SPARK_BC dump or analysis folder —
ears (STT) → question → model → speaking (TTS). Inspired by clear "ask
the binary" product loops elsewhere; **not** an OpenBin SaaS clone and
**not** gated on OpenBin login. OpenBin remains a separate research/lab
note … Dump / `--compile` / `--run-bc` stay SoT. Companions:
`./spark-stt-tts` · brain: owned `spark-coder` (TinyCoder) and/or
dump-fact answers …"

NEW: "Ask questions about a compiled Spark program — by text or by
voice. Recognition, the answer pass, and synthesis all run locally.
Answers come from the decoded dump first; when the evidence runs out,
Spark abstains instead of guessing."

Answer quality — OLD: "1. **Dump facts** — opcodes, sha256, magic SPBC,
TRAIN presence answered from decoded dump (preferred SoT). 2.
**TinyCoder** — when `models/spark-coder/weights.safetensors` exists,
inject dump excerpt + question; greedy generate. 3. **Weak / missing** —
note: TinyCoder is **tiny**, not OpenBin-level RE Q&A, Prefer
`dump.txt` / `ops.json`."

NEW: "1. **Dump facts** — opcodes, checksums, headers, training
operations — answered straight from the decoded dump. 2. **Model
answers** — when the in-repo coding model is trained, it answers with
the dump as context. 3. **Otherwise, Spark says so** — and points you at
the dump files."

Quick start, modes table, gates, tests, grounding sections — keep
(factual docs). In the Grounding section keep: "abstain unless expect /
fixture / dump match" — that is the real differentiator, stated as
behavior.

## 6.3 `voice.html` (source `docs/VOICE.md`)

Intro blurb — OLD: "AI voice `listen`/`speak` (STT/TTS), `reviewer`,
`coder` (codifer), `copier`, written voice models, and PSTN (off by
default). Asm: `asm/voice_ops.s`. Companions: `./spark-stt-tts`,
`./spark-pstn-dial`. … Spark stays a generic language; optional vendor
voice ids are config only."

NEW: "Spark programs can listen and speak. Recognition and synthesis run
on your machine with open speech models — offline after a one-time
download. The same surface covers audio review, voice-driven coding, and
telephony integrations, which stay off unless you explicitly enable
them."

Remainder of the page (syntax, live STT/TTS modes, gates, reviewer,
coder, copier, written models) is reference documentation — keep, with
two text fixes:

- "stub transcript + tiny WAV marker" → "offline stub transcript and WAV
  marker" (drop "tiny").
- Any "owned" phrasing about the STT/TTS models → "open weights, fetched
  once, verified by checksum" (the models are MIT / Apache-2.0 open
  weights; what is ours is the pipeline around them).

---

# 7. Application notes for the HTML pass

1. **Version strings are inconsistent across pages**: index trust strip
   and footer say v0.6.56, about/workflow footers say v0.6.3, downloads
   placeholders say 0.6.0. Unify to the current release everywhere.
2. **Keep every command block verbatim** unless this deck lists a
   replacement. Commands and config tables are documentation, not
   marketing prose; the banned list applies to prose, headings, and
   meta.
3. **Do not change nav structure, anchors, or link targets** — copy
   only.
4. The voice pages assume the voice-real-weights branch has landed
   (`./spark-voice fetch`, `stt_real`, `tts_real`, `eval_real`). If the
   application pass runs before that merge, hold sections 6.1's
   three-step block and outputs list.
5. Grep sweep after applying: `Claude`, `beats`, `theater`, `tiny`,
   `honest`, `LoRA`, `not a `, `fixtures` (in prose), `SPARK_TRAIN_URL`
   (outside terminal blocks and docs tables) — every hit on a public
   page needs a human look.
6. This deck intentionally does not touch `CHANGELOG.html`,
   `playground.html`, `try.html`, `weight-playground.html`, or the
   `learn/` and `docs/knowledge-*` pages. If the pass wants them
   included, that is a follow-up deck.

---

*Deck author: Cursor agent, 2026-09-10. Source of truth for capabilities:
repo Makefile, `tools/spark-voice/`, `python/sparklang/voice_easy/`,
`docs/`. Owner direction quoted at top.*
