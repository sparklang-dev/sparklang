# Spark IDE

Honest status of programming Spark in an IDE **today**.

Today’s `./spark` ELF is the **GAS scaffold** for IDE ops (`asm/`).
**Authoring SoT DECIDED (A+B+C):** destination self-host in Spark (A);
thin C bootstrap (B); Spark-native assembler (C). GAS is disposable —
not forever SoT. Do **not** start a Rust/Python VM from this lane.

**Honesty:** not Electron / not PyQt / not a full IDE product chrome.
Verified ops only — no invented menus or debugger.

| Path | What it is | Status |
|------|------------|--------|
| `ide` language ops | `ide new\|open\|save\|run\|buffer\|ask\|show` | **Works** — §1 |
| open→save→reopen | `examples/ide_save_reopen.spark` + sha256 | **Works** — `11ab006` |
| `ide keys` / `ide key` | Keymap loop (quit/save/run/open/show) | **Works** — §1b |
| Paint bind | status path strip + gutter + AI strip → PPM | **Works** — `b029a4a` |
| Cursor workspace | `make ide` interim editor host | **Works** — not the product |
| CLI `./spark --dry-run` / `--live` | Primary runtime today | **Works** |
| Electron / VS Code fork | — | **Not the product** |
| PyQt IDE shell | — | **Not built** |
| Runtime rewrite | A+B+C **DECIDED**; GAS scaffold | **In progress** — see SELF_HOST.md |

---

## 1. IDE core ops (real on today’s scaffold)

Implemented in `asm/ide_ops.s` on the current `./spark` binary
(`kw_ide` → keys lane first, else `ide_ops_dispatch`). Scaffold path —
not a claim that GAS is the permanent VM.

| Op | Behavior |
|----|----------|
| `ide new` | Clear in-memory buffer (+ optional `"path"` sets path, empty body) |
| `ide open "path"` | Load file into buffer; remember path |
| `ide save` / `ide save "path"` | Write buffer to path (`out/ide/` mkdir as needed) |
| `ide buffer` / `ide buffer -> shown` | Terminal dump of buffer (display SoT for core); bind optional |
| `ide run` | Flush buffer to path or `out/ide/buffer.spark`; `fork`/`exec` `./spark` |
| `ide ask` [`"instruction"`] | Buffer (+ optional quote) → real `ask_run_prompt` |
| `ide show` [`"path.ppm"`] | After paint: `engine_window_show` → dry validate / live `./spark-engine-show` |

Proven **`ide new` chain** (core only — not keymap `n`):
`examples/ide_new_chain.spark` — new with path → buffer → save
(0-byte blank) → open → buffer. Dirty `*` after new; cleared on
save/open.

Proven **`ide buffer` forms** (bare + bind — after quit `54b005e`):
`examples/ide_buffer_forms.spark` — open → `ide buffer -> shown`
(nonempty dump) → `ide new` → bare `ide buffer` (empty). Both emit
`{"op":"ide.buffer","ok":true}`. Bind does **not** dispatch as
`ide show` (buffer matched before show — `"shown"` contains
`"show"`). open→dirty→save `*` e2e not repeated here
(`ide_dirty_status` / `ide_new_chain` already cover it).

Proven **`ide save` forms** (quoted path + bare — after buffer
`96b484c`): `examples/ide_save_forms.spark` — open →
`ide save "out/ide/ide_save_forms_rt.spark"` → bare `ide save`
(rewrites remembered path). Both emit
`{"op":"ide.save","ok":true,"dirty":false}`; file sha256/size ==
`examples/hello.spark`. Bare after open of hello would overwrite the
fixture — quote first (sets path), then bare.

Proven **`ide show` forms** (bare + quoted `.ppm` — after keys-open):
`examples/ide_show_forms.spark` — open → bare `ide show` →
`ide show "out/ide/editor.ppm"`. Both emit
`{"op":"ide.show","ok":true,"via":"spark-engine-show"}` and dry-
validate the same default PPM path in `show.json`.

Proven **`ide ask` forms** (bare + quoted instruction — after show
forms `d2fdc64`): `examples/ide_ask_forms.spark` — open → bare
`ide ask` → `ide ask "Explain gravity briefly"`. Both emit
`{"op":"ide.ask","ok":true,"via":"ask_run_prompt"}` with dry fixture
Gravity; quoted instruction is echoed before the buffer ask body.

Proven **`ide new` forms** (bare + quoted path — after keys-long
`40ff5a6`): `examples/ide_new_forms.spark` — bare `ide new` →
`ide new "out/ide/ide_new_forms_blank.spark"`. Both emit
`{"op":"ide.new","ok":true,"dirty":true}`; quoted prints path arrow.
Keymap `n`→new still **not** invented.

Proven **`ide run` forms** (bare + `-> ran` — after long-srs
`a08293a`): `examples/ide_run_forms.spark` — open → `ide run -> ran`
→ bare `ide run`. Both emit
`{"op":"ide.run","ok":true,"mode":"dry-run"}` with child Gravity.

**`ide ask` (AI strip):** dry uses the same fixture picker as language
`ask` (`pick_ask_reply_ptr` — e.g. Gravity). Live forks
`./spark-ask-http`. Updates paint AI panel via `ide_ai_set`, then
rewrites `out/ide/editor.ppm`. Examples: `examples/ide_ask.spark`,
`examples/ide_ask_forms.spark` (bare + quote).

**`ide show` (display window):** reuses the real engine B path
(`asm/engine_window.s` + companion `tools/browser/spark_engine_show.c`).
Default PPM is `out/ide/editor.ppm` (after `open`/`ask` paint). Dry-run
validates P6 and writes `out/browser/show.json` (no X11). `--live` forks
`./spark-engine-show --ppm …`. Optional quote must be a `.ppm` / `.rgb`.
Example: `examples/ide_show.spark`. No Electron.

**Paint wire (status strip `b029a4a` + dirty `*` + AI panel):** core
exports `ide_buf` / `ide_buf_len` / `ide_dirty`. After `new`/`open`/
`save`, core binds paint **and** writes `out/ide/editor.ppm` (top
**status path bar** via `ide_status_set` + gutter + glyphs + cursor +
bottom AI strip). Buffer edit (`ide new`) sets dirty → status appends
`*` (also `out/ide/status_dirty.txt`); `open`/`save` clear dirty.
Paint owns `ide_cursor`, `ide_status_set`, and `ide_ai_set`. Standalone
`make test-ide-paint` / `ide_status_strip_ppm` prove the paint ELF.
There is **no** `ide paint` language statement. Keymap `n`→new is
**not** proven — do not invent that token.

**Dry-run safe:** parent `--dry-run` → child always `./spark --dry-run <file>`.
Parent `--live` → child `--live`. No network invented by `ide` itself.

**E2E dry (usable now):**

```bash
./spark --dry-run examples/ide_hello.spark
# ide.open → out/ide/editor.ppm (P6)
# ide.run  → child ./spark --dry-run … + Gravity

./spark --dry-run examples/ide_ask.spark
# ide.open → editor.ppm; ide ask → fixture (Gravity) + AI strip
# live: ./spark --live examples/ide_ask.spark → spark-ask-http

./spark --dry-run examples/ide_show.spark
# ide.open → editor.ppm; ide show → engine validate + show.json
# live: ./spark --live examples/ide_show.spark → spark-engine-show

./spark --dry-run examples/ide_run_show.spark
# ide.open → editor.ppm; ide run → child; ide show → show.json
# live: ./spark --live examples/ide_run_show.spark → run + spark-engine-show

./spark --dry-run examples/ide_ask_show.spark
# ide.open → editor.ppm; ide ask → fixture + AI strip; ide show → show.json
# live: ./spark --live examples/ide_ask_show.spark → ask-http + spark-engine-show

./spark --dry-run examples/ide_save_reopen.spark
# ide.open → save → reopen; out/ide/ide_saved_rt.spark sha256==hello.spark
```

### 1b. Keymap / command loop (`asm/ide_keys.s`)

Dispatched before core when the line is `ide keys` or `ide key …`.

| Op | Behavior |
|----|----------|
| `ide keys "script"` | Read command file list; run quit/save/run/open/show |
| `ide key quit\|save\|run\|open\|show ["path"]` | Single keymap command |
| Script tokens | `q`/`quit`, `s`/`save`, `r`/`run`, `o path`/`open path`, `w`/`show` |

**Dry-run:** prints `{"op":"ide.keys",…}` traces (and appends
`out/ide/keys_trace.jsonl`). Open still uses real `open`+`read` into
shared `ide_buf`, then paints `out/ide/editor.ppm`. Show dry-validates
via `engine_window_show` (live: `./spark-engine-show`). Save/run do
**not** write/fork under dry-run (live: write + fork `./spark --dry-run`).

```bash
./spark --dry-run examples/ide_keys.spark
# wire proof: ide key open … then ide key show → editor.ppm + show.json

./spark --dry-run examples/ide_keys_save.spark
# proven keys: script `s` → {"cmd":"save"} + path; dry no write

./spark --dry-run examples/ide_keys_run.spark
# proven keys: script `r` → {"cmd":"run"} + path; dry no fork
# landing `ff7b545` (example + cmds_run.txt + report stamp)

./spark --dry-run examples/ide_keys_quit.spark
# proven keys: script `q` → {"cmd":"quit"} + path; ends loop
# after new-chain `9ed6112` (example + cmds_quit.txt)

./spark --dry-run examples/ide_keys_show.spark
# proven keys: script `w` → {"cmd":"show"} + path; dry validates PPM
# after save-forms `0996802` (example + cmds_show.txt)

./spark --dry-run examples/ide_keys_open.spark
# proven keys: script `o path` → {"cmd":"open"} + paint; after `06aae20`

./spark --dry-run examples/ide_keys_long.spark
# proven keys: script `open`/`quit` long forms (aliases of o/q)

./spark --dry-run examples/ide_keys_long_srs.spark
# proven keys: script `save`/`run`/`show` long forms (aliases of s/r/w)

./spark --dry-run examples/ide_keys_unknown.spark
# proven keys: unknown token -> ok:false; quit ends loop

./spark --dry-run examples/ide_save_nopath.spark
# fail-loud: bare save with no path -> rc!=0

./spark --dry-run examples/ide_run_nobuf.spark
# fail-loud: bare run with empty buffer -> rc!=0

./spark --dry-run examples/ide_ask_nobuf.spark
# fail-loud: bare ask with empty buffer -> rc!=0

./spark --dry-run examples/ide_open_nopath.spark
# fail-loud: bare open with no path quote -> rc!=0

./spark --dry-run examples/ide_bind_forms.spark
# open -> opened; save -> saved; print both JSON ok

./spark --dry-run examples/ide_status_path.spark
# open hello; status.txt == examples/hello.spark (no *)

./spark --dry-run examples/ide_ask_bind.spark
# open → ask -> reply → print reply (Gravity)

./spark --dry-run examples/ide_open_miss.spark
# fail-loud: open missing path → rc!=0

./spark --dry-run examples/ide_show_miss.spark
# fail-loud: show missing .ppm → rc!=0

./spark --dry-run examples/ide_show_notppm.spark
# fail-loud: show .spark (not P6/.rgb) → rc!=0

./spark --dry-run examples/ide_keys_miss.spark
# fail-loud: keys missing cmds script → rc!=0

./spark --dry-run examples/ide_run_bind.spark
# open → run -> ran → print ran (op JSON, not Gravity)

./spark --dry-run examples/ide_new_bind.spark
# new -> created → print created (op JSON)

./spark --dry-run examples/ide_ask_quote_bind.spark
# open → ask "…" -> reply → print Gravity

./spark --dry-run examples/ide_key_bad.spark
# fail-loud: ide key x → rc!=0 (want quit|save|run|open|show)

./spark --dry-run examples/ide_buffer_bind.spark
# open → buffer -> dump → print dump (op JSON)

./spark --dry-run examples/ide_keys_bare.spark
# bare ide keys → default cmds.txt (open…quit)

./spark --dry-run examples/ide_key_open_nopath.spark
# soft-fail: ide key open (no path) → ok:false, rc=0

./spark --dry-run examples/ide_open_bind.spark
# open -> opened → print opened (op JSON)

./spark --dry-run examples/ide_save_bind.spark
# open → save -> saved → print saved (op JSON)

./spark --dry-run examples/ide_status_new_star.spark
# new with path → status.txt ends with *

./spark --dry-run examples/ide_key_quit_alone.spark
# bare ide key quit → ok:true + keys_trace

./spark --dry-run examples/ide_status_clear.spark
# new + save → status.txt path without *

./spark --dry-run examples/ide_key_show_alone.spark
# bare ide key show → editor.ppm + keys_trace

./spark --dry-run examples/ide_dirty_status.spark
# open clean → new dirty (*) → save clean; status_dirty.txt ends *

./spark --dry-run examples/ide_new_chain.spark
# new (dirty *) → buffer → save 0-byte clean → open → buffer

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

**Proven script tokens (real — do not invent others):**

| Token | Cmd | Dry | Live |
|-------|-----|-----|------|
| `o path` / `open` | open | real read + paint | same |
| `s` / `save` | save | JSON trace only | write buffer |
| `r` / `run` | run | JSON trace only | fork `./spark --dry-run` |
| `w` / `show` | show | validate PPM | `./spark-engine-show` |
| `q` / `quit` | quit | end loop | end loop |

Long-form proof: `examples/ide_keys_long.spark` +
`examples/fixtures/ide/cmds_long.txt` (`open` / `quit` aliases of
`o` / `q` — not new tokens). Also
`examples/ide_keys_long_srs.spark` +
`examples/fixtures/ide/cmds_long_srs.txt` (`save` / `run` / `show`
aliases of `s` / `r` / `w`). Unknown script token proof:
`examples/ide_keys_unknown.spark` +
`examples/fixtures/ide/cmds_unknown.txt` (`x` →
`"cmd":"unknown","ok":false` — not invented as a real cmd).

Fail-loud (core, exit non-zero): `examples/ide_save_nopath.spark`
(bare `ide save` with no path);
`examples/ide_run_nobuf.spark` (bare `ide run` with empty buffer);
`examples/ide_ask_nobuf.spark` (bare `ide ask` with empty buffer);
`examples/ide_open_nopath.spark` (bare `ide open` with no path).

Proven **open/save binds** (`-> opened` / `-> saved` — after
open-nopath): `examples/ide_bind_forms.spark` — print bound JSON;
saved file sha == hello.

Proven **status path** after open: `examples/ide_status_path.spark` —
`out/ide/status.txt` equals opened path (no trailing `*`).

Proven **ask bind** (`-> reply`): `examples/ide_ask_bind.spark` —
`print reply` shows dry fixture Gravity (reply text, not op JSON).

Fail-loud open miss: `examples/ide_open_miss.spark` (cannot read path).

Fail-loud show miss: `examples/ide_show_miss.spark` (cannot open image).

Fail-loud show not-PPM: `examples/ide_show_notppm.spark` (not P6/.rgb).

Fail-loud keys miss: `examples/ide_keys_miss.spark` (cannot open command script).

Proven **run bind** (`-> ran`): `examples/ide_run_bind.spark` —
`print ran` shows op JSON (not child Gravity text; contrast ask bind).

Proven **new bind** (`-> created`): `examples/ide_new_bind.spark` —
`print created` shows op JSON (dirty true).

Proven **quoted ask bind**: `examples/ide_ask_quote_bind.spark` —
`ask "…" -> reply` + `print reply` → Gravity (same as bare ask bind).

Fail-loud `ide key` bad token: `examples/ide_key_bad.spark`
(`ide key x` → want quit|save|run|open|show; not keymap `n`).

Proven **buffer bind** (`-> dump`): `examples/ide_buffer_bind.spark` —
`print dump` shows op JSON (body dumps to arrow; contrast ask bind).

Proven **bare `ide keys`**: `examples/ide_keys_bare.spark` — no path
uses asm `default_cmds` → `examples/fixtures/ide/cmds.txt`.

Soft-fail `ide key open` (no path): `examples/ide_key_open_nopath.spark`
— `open path failed` + `"ok":false`, process rc=0 (not hard fail).

Proven **open bind** (`-> opened`): `examples/ide_open_bind.spark` —
`print opened` shows op JSON.

Proven **save bind** (`-> saved`): `examples/ide_save_bind.spark` —
`print saved` shows op JSON.

Proven **status * after new**: `examples/ide_status_new_star.spark` —
`out/ide/status.txt` equals path + trailing `*` (complements clean
`ide_status_path`).

Proven **bare `ide key quit`**: `examples/ide_key_quit_alone.spark` —
quit alone ok:true; appends `out/ide/keys_trace.jsonl`.

Proven **status clear after save**: `examples/ide_status_clear.spark` —
new then save => `status.txt` path with no trailing `*`.

Proven **bare `ide key show`**: `examples/ide_key_show_alone.spark` —
show alone validates `editor.ppm` + keys_trace cmd show.

No `n`/`new` keymap token (core `ide new` only). No mouse GUI in this lane.

---

## 2. Open the Cursor workspace (editor host)

```bash
make ide
# equivalent:
./tools/open-spark-ide.sh
```

This opens Cursor on `spark.code-workspace` with `.spark` grammar + Bifrost.
It is **not** a substitute for the `ide` ops above.

### Workspace folders

1. Spark (language) — this repo  
2. Spark Browser — `../spark-browser`

### Tasks

| Label | Command |
|-------|---------|
| `spark: make` | `make` |
| `spark: test` | `make test` |
| `spark: dry-run hello` | `./spark --dry-run examples/hello.spark` |
| `spark: machine-proof` | `make machine-proof` |
| `spark: live ask` | `./spark --live examples/ask_live.spark` |

Agent card: [AGENTS.md](../AGENTS.md). Rules:
`.cursor/rules/spark-ide-ai-coding.mdc`, `spark-language.mdc`.

### AI coding (gateway)

| Surface | Endpoint | Models |
|---------|----------|--------|
| Cursor Override (when ON) | `http://127.0.0.1:4010/cursor/v1` | Bifrost aliases `fast` / `code` / `code-bulk` / `code-max` / `best` |
| Terminal live `ask` | `AI_GATEWAY_URL=http://127.0.0.1:4000` + Bearer `sk-bf-*` | `model` in `.spark` |

Never commit keys. Never route coding to voice GPU aliases.
Public Bifrost probes use a gateway probe credential only — [ASK_LIVE.md](ASK_LIVE.md).

### AI coding playbooks (catalog)

Pick a playbook without hunting docs:

| Surface | How |
|---------|-----|
| Website playground | Preset → **AI playbooks** optgroup (`/playground.html`) |
| VS Code / Cursor snippets | prefixes `spark-playbook-*` (extension snippets) |
| Repo SoT | `lib/playbooks.spark` + `bootstrap/fixtures/playbooks/` |

Regenerate catalog (committed JSON + snippets):

```bash
make playbooks-catalog
```

**Honest site run:** the playground has **no WASM** Spark runtime.
Selecting a playbook only loads fixture source into the editor.
**Run dry-run** for a playbook **fails loud** with a
[Downloads](https://sparklang.dev/downloads.html) link — it does **not**
fake AI dry-run output. Real dry-run:

```bash
./spark-bootstrap --dry-run bootstrap/fixtures/playbooks/explain_code.spark
make test-ai-playbooks
```

See [AI_PLAYBOOKS.md](AI_PLAYBOOKS.md).

---

## 3. CLI workflow (always the runtime SoT)

```bash
make
./spark --dry-run examples/hello.spark
./spark --dry-run examples/ide_hello.spark
make test
```

Live ask (only when you intend network + gateway):

```bash
export AI_GATEWAY_URL=http://127.0.0.1:4000
export OPENAI_API_KEY=…
./spark --live examples/ask_live.spark
```

ELF flags (from `./spark` with no args): `--dry-run`, `--live`,
`--allow-net`, `--allow-net-capture`, `--pstn-live`, `--version` only.

---

## 4. Language coding loop (codegen — not buffer IDE)

```bash
./spark --dry-run examples/ide.spark
# writes out/program.spark via implement
```

Same ops as `examples/review_builder.spark`. Static review only — never
`eval`s JS.

---

## 5. What is not built

- Electron / Code-OSS wrapper marketed as Spark IDE
- PyQt IDE chrome
- Project wizards, debugger UIs, invented menus
- Full self-host compiler (A seeds + lex goldens only — SELF_HOST.md)

---

## 6. Related

- [AI_PLAYBOOKS.md](AI_PLAYBOOKS.md)
- [PROGRAMMING_GUIDE.md](PROGRAMMING_GUIDE.md)
- [SELF_HOST.md](SELF_HOST.md) (A+B+C)
- [AGENTS.md](../AGENTS.md)
- [LANGUAGE.md](LANGUAGE.md)
- [ASK_LIVE.md](ASK_LIVE.md)
- Reports (local): `spark-ide-ask-20260831.md` (`dc54d92`),
  `spark-ide-show-20260831.md` (`efa2d90`),
  `spark-ide-ask-show-20260831.md` (`b58ab9f`),
  `spark-ide-status-strip-20260831.md` (`b029a4a`),
  `spark-ide-save-reopen-20260831.md` (`11ab006`),
  `spark-ide-dirty-status-20260831.md` (dirty `*` after `ide new`),
  `spark-ide-new-chain-20260831.md` (proven `ide new` chain),
  `spark-ide-buffer-forms-20260831.md` (proven `ide buffer` bare+bind),
  `spark-ide-save-forms-20260831.md` (proven `ide save` bare+quoted),
  `spark-ide-keys-run-20260831.md` (`ff7b545`),
  `spark-ide-keys-quit-20260831.md` (proven `q` → quit),
  `spark-ide-keys-show-20260831.md` (proven `w` → show),
  `spark-ide-keys-open-20260831.md` (proven `o` → open),
  `spark-ide-keys-long-20260831.md` (proven `open`/`quit` long forms),
  `spark-ide-keys-long-srs-20260831.md` (proven `save`/`run`/`show` long),
  `spark-ide-keys-unknown-20260831.md` (proven unknown → ok:false),
  `spark-ide-show-forms-20260831.md` (proven `ide show` bare+quoted),
  `spark-ide-ask-forms-20260831.md` (proven `ide ask` bare+quoted),
  `spark-ide-new-forms-20260831.md` (proven `ide new` bare+quoted),
  `spark-ide-run-forms-20260831.md` (proven `ide run` bare+bind),
  `spark-ide-save-nopath-20260831.md` (proven save nopath fail-loud),
  `spark-ide-run-nobuf-20260831.md` (proven run empty fail-loud),
  `spark-ide-ask-nobuf-20260831.md` (proven ask empty fail-loud),
  `spark-ide-open-nopath-20260831.md` (proven open needs-path fail-loud),
  `spark-ide-bind-forms-20260831.md` (proven open/save -> binds),
  `spark-ide-status-path-20260831.md` (proven status.txt after open),
  `spark-ide-ask-bind-20260831.md` (proven ask -> reply print),
  `spark-ide-open-miss-20260831.md` (proven open miss fail-loud),
  `spark-ide-show-miss-20260831.md` (proven show miss fail-loud),
  `spark-ide-show-notppm-20260831.md` (proven show not-PPM fail-loud),
  `spark-ide-keys-miss-20260831.md` (proven keys miss fail-loud),
  `spark-ide-run-bind-20260831.md` (proven run -> ran print JSON),
  `spark-ide-new-bind-20260831.md` (proven new -> created print JSON),
  `spark-ide-ask-quote-bind-20260831.md` (proven quoted ask -> reply),
  `spark-ide-key-bad-20260831.md` (proven ide key bad-token fail-loud),
  `spark-ide-buffer-bind-20260831.md` (proven buffer -> dump print JSON),
  `spark-ide-keys-bare-20260831.md` (proven bare ide keys default cmds),
  `spark-ide-key-open-nopath-20260831.md` (proven key open nopath soft-fail),
  `spark-ide-open-bind-20260831.md` (proven open -> opened print JSON),
  `spark-ide-save-bind-20260831.md` (proven save -> saved print JSON),
  `spark-ide-status-new-star-20260831.md` (proven status.txt * after new),
  `spark-ide-key-quit-alone-20260831.md` (proven bare ide key quit),
  `spark-ide-status-clear-20260831.md` (proven status.txt clear after save),
  `spark-ide-key-show-alone-20260831.md` (proven bare ide key show)
