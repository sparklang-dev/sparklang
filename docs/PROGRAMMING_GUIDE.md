# Program with Spark

**Canonical programming guide** for the Spark language.
Statement reference: [LANGUAGE.md](LANGUAGE.md).

**Primary today:** CLI `./spark` (this guide). Verified IDE language ops:
`ide new|open|save|run|buffer|ask|show` and `ide keys` / `ide key` —
[IDE.md](IDE.md). Editor paint is a **wire + PPM** (gutter/glyphs + AI
strip; `make test-ide-paint`), not a `.spark` statement. `ide show`
reuses real `spark-engine-show`. Do not invent more.

**Rule:** ops and flags below match `asm/` dispatch, shipped
`examples/*.spark`, and commands verified under `--dry-run` (or companion
`--dry`) on this tree. If something is not listed here, do not assume it
exists.

| Doc | Role |
|-----|------|
| This file | How to build, run, and write `.spark` (CLI) |
| [IDE.md](IDE.md) | Verified `ide` ops; interim editor optional |
| [LANGUAGE.md](LANGUAGE.md) | Full statement reference |
| [ABSTAIN_HEADS.md](ABSTAIN_HEADS.md) | IDK / abstain heads + `./spark-abstain`; flagship `examples/no_invent.spark` |
| [ASK_LIVE.md](ASK_LIVE.md) | Optional live gateway `ask` |
| [VOICE.md](VOICE.md) | STT/TTS / PSTN |
| [Model aspects](MODEL_ASPECTS.md) | Behaviors, ears/eyes/speaking, thinking, tools |
| [ENCRYPT_GATEWAY.md](ENCRYPT_GATEWAY.md) | Encrypt-to-model |
| [MODEL_ANALYSIS.md](MODEL_ANALYSIS.md) | Model analyze/improve |
| [OS_DESIGN.md](OS_DESIGN.md) | OS blueprints |
| [SELF_HOST.md](SELF_HOST.md) | A+B+C self-host path (GAS scaffold → B/C → Spark) |

**Repos:** language SoT = this `spark` repo. Browser product host =
sibling `spark-browser` (Qt shim). Engine-B asm examples exist in-repo
(see §10); they are not a substitute for the language CLI workflow.

---

## 1. What Spark is

You write **`.spark` files**. Today they run on the shipped `./spark`
ELF **GAS scaffold** (`asm/`). **Authoring SoT DECIDED (A+B+C):**
self-host destination (A), thin C bootstrap (`bootstrap/`), Spark-native
assembler (`sparkasm/`). Do not treat GAS as forever SoT; do not start
a Rust/Python VM from IDE work. See [SELF_HOST.md](SELF_HOST.md).

**Scope:** not full ES / not full CSS / not a full compiler /
not Google.com parity / not Electron. Fixture HTML + proven ops only.

| Tier (today) | What | Path |
|------|------|------|
| Machine code | CPU runs ELF | `./spark` (GAS scaffold) |
| Assembly scaffold | GAS → `as` → `ld` | `asm/*.s` (disposable) |
| B bootstrap | Thin C dry VM | `bootstrap/` → `spark-bootstrap` |
| C assembler | `.sasm` → ELF `.o` | `sparkasm/` (phase-1) |
| HDL (optional stub) | classify sketch | `hdl/classify_score.v` |

Live HTTP for `ask` is a **companion** (`./spark-ask-http`) forked only
under `--live`. Dry-run does not dial the network for ask.

This is **not** Apache Spark / Databricks.

---

## 2. Build

```bash
make # ./spark + companions
./spark --version # e.g. spark 0.6.0 (x86_64 asm + companions)
make machine-proof # file(1) + objdump of _start
```

| Target | Role |
|--------|------|
| `make` / `make all` | VM + companions |
| `make test` | `tests/run_dry.sh` + HDL check |
| `make test-examples` | every `examples/*.spark` under `--dry-run` |
| `make test-host-embed` | Python / JS / C host embed + `--embed` handshake |
| `make test-shell` | Live `--allow-shell` argv `execve` (echo\|true\|false) |
| `make test-e2e-browser` | browser dry E2E (no display) |
| `make sparkbc-e2e` | SPARK_BC TRAIN→STEP→ARTIFACT (dry; not SGD) |
| `make ide` | interim editor workspace open (not product IDE) |
| `make clean` | remove ELF + companion binaries |

If `make` fails on `asm/engine_*.s` while parallel engine work is in
flight, that is an engine-lane assemble/link issue — not a reason to
invent a different language runtime. Re-run `make` when those objects
link; language examples below were verified when `./spark` was present.

---

## 3. Run: dry vs live

Verified usage from bare `./spark`:

```
Usage: spark --dry-run [--allow-net] [--allow-net-capture] [--allow-shell] <file.spark>
 spark --live [--allow-shell] <file.spark>
 spark --live --pstn-live <file>
 spark --version
```

There is **no** `./spark ide` ELF subcommand. IDE core is **language
ops** (`ide open|save|run|…`) — [IDE.md](IDE.md),
`examples/ide_hello.spark`.

```bash
./spark --dry-run examples/hello.spark
./spark --dry-run examples/ide_hello.spark

export AI_GATEWAY_URL=http://127.0.0.1:4000
export OPENAI_API_KEY=… # sk-bf-*; never commit
./spark --live examples/ask_live.spark
```

| Flag / gate | Effect |
|-------------|--------|
| `--dry-run` | Offline / fixture path (CI) |
| `--live` | Live companions (ask, speech, GUI, …) |
| `--allow-net` | `review url` may fetch remote `http(s)` |
| `--allow-shell` | With `--live`: gated `execve` of `echo`/`true`/`false` via `./spark-shell`. Dry-run still fixtures. Never `system()`. |
| `--pstn-live` + `SPARK_PSTN=1` | PSTN dial (off by default) |

### Host embed (Python, JS, C)

Call Spark from a host language — dry-run default, same fixtures as CLI:

```bash
PYTHONPATH=python python -c "
from sparklang import run
r = run('examples/hello.spark')
print(r.stdout)
assert r.ok
"
PYTHONPATH=python python -m sparklang examples/hello.spark
node -e "console.log(require('./js/sparklang').run('examples/hello.spark').ok)"
make examples/c/host_embed && ./examples/c/host_embed
./spark --embed # JSON handshake: api=python,js,c
make test-host-embed
make test-shell
```

Package lives in `python/sparklang/`, `js/sparklang/`, `host/c/`.
See [LANGUAGE.md](LANGUAGE.md) (`shell` / `run` / host embed) and
[ADOPTION_BAR.md](ADOPTION_BAR.md).

---

## 4. First program

File: `examples/hello.spark` (verified `rc=0` under `--dry-run`):

```
model code

ask "Explain gravity in one sentence" -> text

print text
```

```bash
./spark --dry-run examples/hello.spark
```

Lexical rules (from LANGUAGE.md / working examples):

- Comments: `#` to end of line
- Strings: `"..."`
- `-> name` binds a result
- `|` may prefix a pipeline step

Optional `spark.toml` documents defaults; the **bootstrap** VM reads
`model = "…"` from cwd on startup. `./spark` (GAS) still needs `model` or
`use` in the `.spark` file. See [LANGUAGE_IMPROVEMENTS.md](LANGUAGE_IMPROVEMENTS.md).

---

## 5. Syntax (verified examples)

### 5.0 DX sugar (`use`, `?`, `say`)

`examples/hello_sugar.spark`, `examples/dx_showcase.spark`

```
model "fixtures/tiny-lm" # explicit HF id / path / configured name

? "Explain gravity in one sentence" -> text # sugar for ask

say "Hello" -> "out.wav" # sugar for speak
```

Bootstrap also supports `include "lib/ai.spark"` and `{var}` interpolation
in ask/`?` prompts — see [LANGUAGE_IMPROVEMENTS.md](LANGUAGE_IMPROVEMENTS.md).

### 5.1 `model` + `ask`

`examples/hello.spark`, `examples/ask_live.spark`

```
model "fixtures/tiny-lm"

ask "Explain gravity in one sentence" -> text
print text
```

Live ask needs `--live` + `./spark-ask-http` + env — [ASK_LIVE.md](ASK_LIVE.md).

### 5.2 `ask probe` / `gateway probe`

`examples/ask_probe.spark`, `examples/gateway_probe.spark` 
(requires companion `./spark-ask-probe`; dry prints probe-credential readiness
JSON, no public HTTP)

```
ask probe -> info
gateway probe -> info
```

```bash
./spark --dry-run examples/ask_probe.spark
./spark-ask-probe --dry
```

Live public probe / HTTP 401 → credential unavailable (exit non-zero);
do not invent routing. See ASK_LIVE.md.

### 5.3 `classify`

`examples/classify_intent.spark`

```
classify Intent { support, sales, spam }
 from "My account is locked and I need help"
 min_confidence 0.7
 -> intent

classify multi Tags { support, sales, spam }
 from "Please help me buy a card, what is the price?"
 -> tags
```

### 5.4 `extract`

`examples/extract_person.spark`

```
extract Person {
 name: string
 age: int
} from "Ada Lovelace was born in 1815" -> person
```

### 5.5 `pipeline`

`examples/pipeline_translate.spark`

```
let doc "Office printers need regular cleaning and toner checks."

pipeline {
 ask "Summarize: {doc}" -> summary
 | ask "Translate to Spanish: {summary}" -> es
}
```

### 5.6 `tool` / `with tools`

`examples/tool_agent.spark`

```
tool weather(city: string) -> string {
 "stub:local"
}

with tools [weather] {
 ask "What's the weather hint for Springfield?" -> answer
}
```

Fail-loud cases live under `examples/neg/` (e.g. `with_no_tool.spark`).

### 5.7 `review` / `builder` / `implement`

`examples/review_builder.spark`, `examples/ide.spark` 
(dry-run writes `out/program.spark`; **not** the product IDE)

```
review path "examples/fixtures/sample.js" -> report
review url "file://examples/fixtures/sample.js" -> report_url
review text "function x(){ eval(y); }" -> report_text

builder prefer lower request "add classify Intent and wire voice turn" -> patch
implement patch into "out/program.spark"
```

Remote `http(s)` review needs `--allow-net`. Never evaluates web JS.

### 5.7b IDE core (`ide`)

Verified (`examples/ide_hello.spark`, `examples/ide_ask.spark`,
`examples/ide_show.spark`, `make test`, ask ship `dc54d92`, this tree
`rc=0`):

```
ide new
ide open "examples/hello.spark" -> opened
ide buffer -> shown
ide save "out/ide/ide_hello_saved.spark" -> saved
ide run -> ran
ide ask -> reply
ide show -> shown
```

| Op | Behavior |
|----|----------|
| `ide new` | Clear buffer (+ optional `"path"`) |
| `ide open "path"` | Load file into buffer |
| `ide save` / `ide save "path"` | Write buffer to path |
| `ide buffer` / `ide buffer -> shown` | Terminal dump of buffer; bind optional (not `show`) |
| `ide run` | Flush; `fork`/`exec` `./spark` (`--dry-run` or `--live`) |
| `ide ask` [`"instruction"`] | Buffer (+ optional quote) → real `ask_run_prompt`; dry fixture (Gravity); live `./spark-ask-http`; AI strip via `ide_ai_set` + `editor.ppm` |
| `ide show` [`"path.ppm"`] | After paint: real `engine_window_show`; dry validates PPM + `show.json`; live forks `./spark-engine-show` |

```bash
./spark --dry-run examples/ide_ask.spark
# dry → fixture reply (e.g. Gravity); live → spark-ask-http

./spark --dry-run examples/ide_show.spark
# dry → validate editor.ppm; live → spark-engine-show

./spark --dry-run examples/ide_run_show.spark
# open → run (child) → show (engine validate + show.json)

./spark --dry-run examples/ide_ask_show.spark
# open → ask (AI strip) → show (engine validate + show.json)

./spark --dry-run examples/ide_save_reopen.spark
# open → save → reopen; saved file sha256/size == hello.spark

./spark --dry-run examples/ide_new_chain.spark
# new → buffer → save (0-byte) → open → buffer; dirty * then clear

./spark --dry-run examples/ide_buffer_forms.spark
# open → buffer -> shown (body) → new → bare buffer; not show

./spark --dry-run examples/ide_save_forms.spark
# open → save "path" → bare save; sha == hello.spark

./spark --dry-run examples/ide_show_forms.spark
# open → bare show → show "editor.ppm"; both ide.show

./spark --dry-run examples/ide_ask_forms.spark
# open → bare ask → ask "instruction"; both Gravity fixture

./spark --dry-run examples/ide_new_forms.spark
# bare new → quoted new path; both dirty true (not keymap n)

./spark --dry-run examples/ide_run_forms.spark
# open → run -> ran → bare run; both dry-run Gravity
```

No PyQt / Electron IDE. Display window = engine companion only.
Details: [IDE.md](IDE.md). Reports:
`reports/spark-ide-ask-20260831.md`,
`reports/spark-ide-show-20260831.md`,
`reports/spark-ide-run-show-20260831.md`,
`reports/spark-ide-ask-show-20260831.md`,
`reports/spark-ide-save-reopen-20260831.md`,
`reports/spark-ide-new-chain-20260831.md`,
`reports/spark-ide-buffer-forms-20260831.md`,
`reports/spark-ide-save-forms-20260831.md`,
`reports/spark-ide-show-forms-20260831.md`,
`reports/spark-ide-ask-forms-20260831.md`,
`reports/spark-ide-new-forms-20260831.md`,
`reports/spark-ide-run-forms-20260831.md`,
`reports/spark-ide-save-nopath-20260831.md`,
`reports/spark-ide-run-nobuf-20260831.md`,
`reports/spark-ide-ask-nobuf-20260831.md`,
`reports/spark-ide-open-nopath-20260831.md`,
`reports/spark-ide-bind-forms-20260831.md`,
`reports/spark-ide-status-path-20260831.md`,
`reports/spark-ide-ask-bind-20260831.md`,
`reports/spark-ide-open-miss-20260831.md`,
`reports/spark-ide-show-miss-20260831.md`,
`reports/spark-ide-show-notppm-20260831.md`,
`reports/spark-ide-keys-miss-20260831.md`,
`reports/spark-ide-run-bind-20260831.md`,
`reports/spark-ide-new-bind-20260831.md`,
`reports/spark-ide-ask-quote-bind-20260831.md`,
`reports/spark-ide-key-bad-20260831.md`,
`reports/spark-ide-buffer-bind-20260831.md`,
`reports/spark-ide-keys-bare-20260831.md`,
`reports/spark-ide-key-open-nopath-20260831.md`,
`reports/spark-ide-open-bind-20260831.md`,
`reports/spark-ide-save-bind-20260831.md`,
`reports/spark-ide-status-new-star-20260831.md`,
`reports/spark-ide-key-quit-alone-20260831.md`,
`reports/spark-ide-status-clear-20260831.md`,
`reports/spark-ide-key-show-alone-20260831.md`.

### 5.7c IDE keymap (`ide keys` / `ide key`)

Verified (`examples/ide_keys.spark`, commit `51fbe8f` + show polish,
save token proof `examples/ide_keys_save.spark`, run token proof
`examples/ide_keys_run.spark`, quit token proof
`examples/ide_keys_quit.spark`, show token proof
`examples/ide_keys_show.spark`, open token proof
`examples/ide_keys_open.spark`, long-form proof
`examples/ide_keys_long.spark`, long-form srs proof
`examples/ide_keys_long_srs.spark`, unknown-token proof
`examples/ide_keys_unknown.spark`, this tree `rc=0`).
Asm: `asm/ide_keys.s`. Script fixtures:
`examples/fixtures/ide/cmds.txt`, `cmds_save.txt` (`s` → save),
`cmds_run.txt` (`r` → run), `cmds_quit.txt` (`q` → quit),
`cmds_show.txt` (`w` → show), `cmds_open.txt` (`o` → open),
`cmds_long.txt` (`open` / `quit` long forms),
`cmds_long_srs.txt` (`save` / `run` / `show` long forms),
`cmds_unknown.txt` (`x` → unknown ok:false).

```
ide keys "examples/fixtures/ide/cmds.txt"

ide key open "examples/hello.spark"
ide key show
ide key save
ide key run
ide key quit
```

| Op | Behavior |
|----|----------|
| `ide keys "script"` | Read command file; run quit/save/run/open/show |
| `ide key quit\|save\|run\|open\|show ["path"]` | Single keymap command |
| Script tokens (proven) | `q`/`quit`, `s`/`save`, `r`/`run`, `o path`/`open path`, `w`/`show` |

```bash
./spark --dry-run examples/ide_keys.spark
# prints {"op":"ide.keys",…}; appends out/ide/keys_trace.jsonl

./spark --dry-run examples/ide_keys_save.spark
# script `s` → {"cmd":"save","path":"examples/hello.spark"}; dry no write

./spark --dry-run examples/ide_keys_run.spark
# script `r` → {"cmd":"run","path":"examples/hello.spark"}; dry no fork

./spark --dry-run examples/ide_keys_quit.spark
# script `q` → {"cmd":"quit","path":"examples/hello.spark"}; ends loop

./spark --dry-run examples/ide_keys_show.spark
# script `w` → {"cmd":"show","path":"examples/hello.spark"}; dry PPM

./spark --dry-run examples/ide_keys_open.spark
# script `o` → {"cmd":"open","path":"examples/hello.spark"}; paints

./spark --dry-run examples/ide_keys_long.spark
# script `open`/`quit` long forms (aliases of o/q)

./spark --dry-run examples/ide_keys_long_srs.spark
# script `save`/`run`/`show` long forms (aliases of s/r/w)

./spark --dry-run examples/ide_keys_unknown.spark
# script `x` → {"cmd":"unknown","ok":false}; quit ends loop

./spark --dry-run examples/ide_save_nopath.spark
# bare save no path → rc!=0

./spark --dry-run examples/ide_run_nobuf.spark
# bare run empty buffer → rc!=0

./spark --dry-run examples/ide_ask_nobuf.spark
# bare ask empty buffer → rc!=0

./spark --dry-run examples/ide_open_nopath.spark
# bare open no path → rc!=0

./spark --dry-run examples/ide_bind_forms.spark
# open -> opened; save -> saved; print JSON

./spark --dry-run examples/ide_status_path.spark
# status.txt == examples/hello.spark

./spark --dry-run examples/ide_ask_bind.spark
# ask -> reply; print reply → Gravity

./spark --dry-run examples/ide_open_miss.spark
# open missing path → rc!=0

./spark --dry-run examples/ide_show_miss.spark
# show missing .ppm → rc!=0

./spark --dry-run examples/ide_show_notppm.spark
# show .spark (not P6/.rgb) → rc!=0

./spark --dry-run examples/ide_keys_miss.spark
# keys missing cmds script → rc!=0

./spark --dry-run examples/ide_run_bind.spark
# run -> ran; print ran → op JSON

./spark --dry-run examples/ide_new_bind.spark
# new -> created; print created → op JSON

./spark --dry-run examples/ide_ask_quote_bind.spark
# ask "…" -> reply; print reply → Gravity

./spark --dry-run examples/ide_key_bad.spark
# ide key x → rc!=0 (want quit|save|run|open|show)

./spark --dry-run examples/ide_buffer_bind.spark
# buffer -> dump; print dump → op JSON

./spark --dry-run examples/ide_keys_bare.spark
# bare ide keys → default cmds.txt

./spark --dry-run examples/ide_key_open_nopath.spark
# ide key open (no path) → ok:false, rc=0

./spark --dry-run examples/ide_open_bind.spark
# open -> opened; print opened → op JSON

./spark --dry-run examples/ide_save_bind.spark
# save -> saved; print saved → op JSON

./spark --dry-run examples/ide_status_new_star.spark
# new path → status.txt ends *

./spark --dry-run examples/ide_key_quit_alone.spark
# bare ide key quit → ok:true + keys_trace

./spark --dry-run examples/ide_status_clear.spark
# new + save → status.txt without *

./spark --dry-run examples/ide_key_show_alone.spark
# bare ide key show → editor.ppm + keys_trace
```

**Dry-run:** traces only for save/run (no write / no fork). Quit ends
the keymap loop. Open still does real `open`+`read` **and** paints
`editor.ppm`. Show dry-validates via `engine_window_show`. No mouse GUI.
Do **not** invent key tokens.

### 5.7d Editor paint (PPM — not a language op)

Verified (`make test-ide-paint`, status strip `b029a4a` + dirty `*`
after `ide new` + AI panel on `dc54d92`, PASS this tree). There is
**no** `ide paint` statement in `.spark`. Paint is asm ABI: core
exports `ide_buf` / `ide_buf_len` / `ide_dirty` and calls
`ide_paint_bind` after `new`/`open`/`save`; `ide ask` calls
`ide_ai_set` then rewrites PPM. Paint owns `ide_cursor` /
`ide_status_set` / `ide_ai_set` and writes `out/ide/editor.ppm` (top
**status path[+*]** + gutter + glyphs + cursor + bottom AI strip).
`ide new` → dirty `*`; `open`/`save` clear. Keymap `n`→new **not**
proven. Example: `examples/ide_dirty_status.spark`.

```bash
make test-ide-paint
# → {"op":"ide.paint","ppm":"out/ide/editor.ppm",…}
# → PASS ide-paint-ppm … / ide_status_strip_ppm
./spark --dry-run examples/ide_dirty_status.spark
# → dirty true on new; status_dirty.txt ends *; save clears
```

Report: `reports/spark-ide-status-strip-20260831.md`,
`reports/spark-ide-dirty-status-20260831.md`.
### 5.8 Voice

`examples/voice_turn.spark` (and VOICE.md examples)

```
voice {
 listen -> user
 classify Intent { support, sales } from user -> intent
 ask "Reply helpfully to: {user}" -> reply
 speak reply -> "out.wav"
}
```

Also present: `voice_reviewer.spark`, `voice_coder.spark`,
`voice_copy.spark`, `voice_model.spark`, `voice_pstn.spark`,
`voice_live.spark`. PSTN stays gated off unless `--pstn-live` +
`SPARK_PSTN=1`.

### 5.9 Browser / MITM (language driver)

Canonical dry entry: `examples/browser_main.spark`

```
browser run "examples/browser_main.spark" -> session
browser goto "https://example.com/" -> page
mitm enable -> mitm_session
mitm filter "example\\.com" -> filt
mitm har export -> har
```

| Mode | Command (verified entrypoints) |
|------|--------------------------------|
| Dry | `./spark --dry-run examples/browser_main.spark` |
| Live product | `cd ../spark-browser && make run` → `./spark --live browser/run.spark` |
| Dry E2E | `make test-e2e-browser` |
| SPARK_BC STEP e2e | `make sparkbc-e2e` |

Also dry examples: `browser_ca.spark`, `browser_h2.spark`,
`browser_quic.spark`, `browser_cdp.spark`, `browser_mitm.spark`,
`browser_show.spark` (PPM show; dry `display:false`; live X11 via
`./spark-engine-show` — see §10 Live X11 show).

`browser gui` requires `--live` (forks `./spark-browser-host`). Dry
`browser gui` fails by design (`examples/neg/browser_gui_dry.spark`).

Do **not** document `python3 -m spark_browser run` as the product entry.

### 5.10 Encrypt gateway

`examples/encrypt_gateway.spark` (needs `./spark-enc-gateway`)

```
crypto keygen -> key
encrypt gateway enable key
gateway encrypt on
encrypt seal text "…" -> blob
encrypt open blob -> plain
ask "…" -> reply
gateway encrypt off
```

### 5.11 Network / binary / CUDA / OS / model

| Area | Example file | Notes |
|------|--------------|-------|
| Network analyze | `network_analyze.spark` | open fixture pcap |
| Capture probe | `network_capture_probe.spark` | `claimed:false` |
| Capture | `network_capture.spark` | fixture unless `--allow-net-capture` |
| Binary | `binary_any.spark` | `out/decompile/…` |
| CUDA / memory | `cuda_mem.spark` | `/dev/nvidia*` |
| PCIe | `cuda_pcie.spark` | sysfs link |
| OS blueprint | `os_agentos.spark` | `out/os/` stubs; never reboot |
| Model improve | `model_improve.spark` | fixtures; build ≠ `train@*` |

---

## 6. Layout

```
examples/*.spark # programs
docs/ # this guide + LANGUAGE.md + …
asm/*.s # VM (do not thrash engine_* from app docs)
tools/ # companions (ask-http, review-url, …)
templates/ # os / browser scaffolds
out/ # implement / HAR / decompile / engine artifacts
tests/ # dry harness
spark.toml # documented defaults (not VM-parsed for aliases)
spark.code-workspace # editor workspace (IDE.md)
```

---

## 7. Debugging

| Symptom | What to check |
|---------|----------------|
| Usage printed | Need `--dry-run` or `--live` plus a `.spark` path |
| Missing companion | `make` / `make companions`; then re-run |
| `ask probe` fail | probe credential path — see ASK_LIVE.md |
| `review url` blocked | Remote needs `--allow-net`; use `file://` offline |
| `browser gui` in dry | Expected fail — use dry `browser run` or `--live` |
| Prefer GPU 2 | Refused (voice GPU) — see `examples/neg/cuda_prefer_*` |

Negative corpus: `examples/neg/` (tests expect **non-zero** exit + error text).

### Errors / exit codes (verified)

| Situation | Observed |
|-----------|----------|
| Bare `./spark` (usage) | exit **1** |
| Success (`examples/hello.spark` dry) | exit **0** |
| Fail-loud language errors (`unknown`, `with_no_tool`, blocked `review url`, …) | exit **non-zero** (typically **1**) + `error:` / gate text |
| `./spark-ask-probe` credential miss | exit **4** (`credential unavailable`) |
| Live net-capture without `CAP_NET_RAW` | exit **4** (`claimed:false`) |

Do not assume every stderr line means a non-zero process exit without checking `$?` (pipes hide the VM’s code unless `set -o pipefail`).

---

## 8. Tests

```bash
make test
make test-examples
make test-e2e-browser
make sparkbc-e2e
make test-ide-paint # PPM paint wire (not a .spark op)
```

`make test` stays offline for ask/vendor speech. If `./spark` disappears
mid-suite while engine objects are relinking, re-run `make` then `make test`.

---

## 9. Hardware / asm

- **Users program in Spark.** The VM is asm→ELF.
- Do not edit `asm/engine_*.s` from an app/docs lane while engine agents
 work that tree.
- `make machine-proof` shows ELF64 + `_start` disassembly when the binary
 links.

---

## 10. Engine B (verified ops only)

Documented here only after dry-run (or gated fail) on this tree.

**Scope:** **Not** a full browser. **Not** full CSS / full ES /
Google.com / Electron. Phase-1 `<script>` → `engine_js_eval` only.
HTTPS is OpenSSL BIO companion `./spark-engine-fetch-tls` — **not**
TLS-in-asm.

### Dry pipeline (fetch→parse→css→layout→paint→show)

`examples/engine_pipeline.spark` (verified on this tree):

```
engine fetch "file://engine/fixtures/style_basic.html" -> body
engine parse "out/engine/body.bin" -> dom
engine css attach -> styles
engine layout -> boxes
engine paint boxes -> ppm
engine show "out/engine/pipeline.ppm" -> shown
```

```bash
./spark --dry-run examples/engine_pipeline.spark
# → out/engine/pipeline.ppm + out/browser/show.json
# {"op":"show","mode":"dry-run","display":false,…}
```

**Table pipeline (real):** `examples/engine_pipeline_table.spark` on
`table_demo.html` — cell borders + cell text (`layout.table` /
`cell_text`). Also `examples/engine_fetch_parse_layout.spark`.
Proofs: `make test-engine-pipeline-table`, `make test-engine-layout`,
`make test-engine-fetch-parse-layout`.

**CSS padding (real):** shorthand `padding` px on block/cell boxes
(`e313b21`); **`border-width` px** on table cells (`60e2b44`); display
subset includes table/table-row/table-cell — **not** full CSS / `%` /
multi-value shorthand.

Artifacts: `out/engine/body.bin`, `out/browser/engine/dom.json`,
`out/browser/engine/css.json`, `out/engine/pipeline.ppm`,
`out/browser/show.json`. Layout without prior parse **fail closed**
(`examples/neg/engine_layout_no_dom.spark`).

### Live X11 show (`spark-engine-show`)

Same `.spark` file; `--live` forks the existing companion (no Qt):

```bash
make spark-engine-show
./spark --live examples/engine_pipeline.spark
# companion: ./spark-engine-show --ppm out/engine/pipeline.ppm --hold 2000
# show.json → mode:live display:true path:out/engine/pipeline.ppm
```

Also: `./spark --live examples/browser_show.spark` (fixture PPM) and
`./spark --live examples/browser_engine_render.spark` (render→same
`pipeline.ppm`). Needs `DISPLAY`. Longer view:

```bash
./spark-engine-show --ppm out/engine/pipeline.ppm --hold 5000
./spark-engine-show --dry --ppm out/engine/pipeline.ppm # no X11
```

Dry `make test` never forks X11. Report:
`reports/spark-engine-show-live-20260831.md`.

### `engine parse` → `out/browser/engine/dom.json`

`examples/engine_parse.spark` (verified `rc=0`):

```
engine parse "engine/fixtures/hello.html" -> dom
```

Writes DOM JSON under `out/browser/engine/dom.json`
(`"op":"engine.parse"`, `"engine":"spark-asm-html"`, node list).

### `engine fetch`

| Input | Flag | Verified result |
|-------|------|-----------------|
| `file://…` / local path | none | OK → `out/engine/body.bin` (`examples/engine_fetch.spark`) |
| `http://127.0.0.1/…` | **without** `--allow-net` | Fail — blocked by default (`examples/neg/engine_fetch_blocked.spark`) |
| `http://127.0.0.1/…` | **with** `--allow-net` | OK — `"transport":"asm-socket"`, `"fetched":true` (loopback fixture) |
| `https://…` | **without** `--allow-net` | Fail closed (`examples/neg/engine_fetch_https.spark`) |
| `https://…` | **with** `--allow-net` | OK — forks `./spark-engine-fetch-tls` OpenSSL BIO (`openssl-bio`) |

```
engine fetch "file://examples/fixtures/engine/sample.html" -> body
# http/https with --allow-net:
# ./spark --dry-run --allow-net your_fetch.spark
```

HTTPS is **not** TLS-in-asm / **not** Python — companion only
(`27252f4`). PASS: `engine_fetch_tls_companion_*` +
`engine_fetch_https_openssl_bio`.

### `js` phase-1 only

Verified: `examples/js_phase1.spark`, `browser/engine/js.spark`.

```
js eval "1+1" -> sum
js eval "'a'+'b'" -> cat
js eval "-1" -> neg
js eval "var x = 1; x+2" -> vsum
js run "console.log(1+1)" -> log
js console -> buf # dump console buffer (browser/engine/js.spark)
js selftest -> ok
```

Runtime prints `phase1 numbers/strings/+/unary- /var-num/console.log (not full ES)`.
Artifacts: `out/engine/js_result.txt`, `out/engine/js_console.txt`.

**DOM hook (real):** `engine parse` walks `<script>` text children and
calls `engine_js_eval` (same phase-1 slice). Proof:
`engine/fixtures/hello.html` (`1+1`), `engine/fixtures/script_log.html`,
`./engine/tests/js_script_dom.sh`.

**Unary `-`:** prefix on a number primary (`-1`, `-1+3`, `--1`).
Binary `-` and `-'str'` fail loud. Not full ES.

**`var` number assign:** `var x = 1` / `var x = 1; x+2` (RHS must be
number). `var x = 'a'`, undeclared `x`, `let`/`const` fail loud.

**Explicitly not yet:** full ES, modules, DOM APIs, `var` strings,
binary `-`, or a JS standard library beyond this phase-1 slice.

Product GUI PyQt spark-browser is **PARKED** — engine B pixels are the
product render SoT. See [SELF_HOST.md](SELF_HOST.md).

---

## 11. Honest gaps (not in the language)

Standard-tutorial topics that are **not** Spark syntax today — omit from
examples; do not invent:

| Topic | Status |
|-------|--------|
| `if` / `while` / `for` | **Not** in shipped examples / LANGUAGE statements |
| User-defined `fn` / modules / imports | **Not** present (tools are `tool` + `with tools`) |
| `include "path"` in `./spark` (GAS) | **Not** yet — bootstrap VM only |
| `{var}` in ask prompts (GAS) | **Not** yet — bootstrap interpolates |
| `ide paint` as a `.spark` op | **Not** — paint is ABI + `make test-ide-paint` |
| Electron / PyQt product IDE chrome | **Not** built — buffer + keys + ask/show + PPM only |
| Full CSS / Google.com | **Not** — fixture HTML + display/padding subset |
| Full ES | **Not** — phase-1 `+` / unary `-` / `var` num / console.log |
| HTTPS TLS inside asm | **Not** — OpenSSL BIO companion under `--allow-net` |
| Full compiler / Stage 4–5 | **Partial** — C `--compile` + `bc_vm` for SPARK_BC.md op families; Spark-hosted compiler not started |

What **is** real: `model` / `ask` / `classify` / `extract` / `pipeline` /
`tool` / `review`→`builder`→`implement` / `voice` / gateway encrypt /
verified `ide` ops / engine B fixture pipeline. A+B+C:
[SELF_HOST.md](SELF_HOST.md), `bootstrap/README.md`,
`sparkasm/README.md`, `selfhost/README.md`.

---

## 12. Cheat sheet

```bash
make && ./spark --version
./spark --dry-run examples/hello.spark
./spark --dry-run examples/ide_hello.spark
./spark --dry-run examples/ide_ask_show.spark
./spark --dry-run examples/ide_save_reopen.spark
./spark --dry-run examples/engine_pipeline.spark
./spark --dry-run examples/engine_pipeline_table.spark
./spark --dry-run examples/js_phase1.spark
make test-bootstrap
make -C sparkasm test
make test-selfhost-lex
make test-sparkbc
make sparkbc-e2e
./spark-bootstrap --compile examples/hello.spark -o /tmp/hello.sparkbc
./spark-bootstrap --run-bc /tmp/hello.sparkbc
# make test-ide-paint # PPM + status strip (not a .spark op)
# optional interim editor: make ide (editor host — see IDE.md)
```

Next: [IDE.md](IDE.md) (verified `ide` ops; CLI stays primary).
