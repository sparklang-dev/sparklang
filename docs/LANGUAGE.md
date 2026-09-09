# Spark language specification

**Programming how-to:**
[PROGRAMMING_GUIDE.md](PROGRAMMING_GUIDE.md) ·
**AI models (user-facing):** [AI_MODELS.md](AI_MODELS.md) ·
**IDE status:** [IDE.md](IDE.md) (verified
`ide new|open|save|run|buffer|ask|show` + `ide keys` / `ide key`;
paint = PPM wire, not a language op; show = real `spark-engine-show`)

Spark is a small, diffable language where **AI is a first-class primitive**.
Programs are `.spark` files. They are interpreted by the **Spark VM**, which
is written in **x86_64 assembly** and shipped as **machine code** (ELF),
not as a Python/Rust/C interpreter.

## Implementation tiers (owner hierarchy)

1. **Machine language** — CPU executes the `spark` binary directly
2. **Assembly** — `asm/spark.s` (GAS) → `as` → `ld` → ELF
3. **HDL** — `hdl/classify_score.v` models parallel label scoring (FPGA optional)

## Lexical rules

- Comments: `#` to end of line
- Strings: `"..."` with `\"`, `\n`, `\t`
- Keywords are ASCII identifiers at statement start
- `->` binds a result name
- `|` may prefix a pipeline step
- **`use <alias>`** — sugar for `model <alias>` (shorter default model line)
- **`? "…"`** — sugar for `ask "…"` (question shorthand)
- **`say "…"`** — sugar for `speak "…"`
- **`include "path"`** — bootstrap VM only; inlines another `.spark` file
- **`{name}`** in ask/`?` prompts — bootstrap interpolates `let` bindings

See [LANGUAGE_IMPROVEMENTS.md](LANGUAGE_IMPROVEMENTS.md) for the full DX changelog.

### `use <id>` / `model <id>`

Set the default model for following calls. Pass an **explicit** HF id,
checkpoint path, or configured gateway model string. SparkLang is **not**
a Bifrost plugin — there is no per-task alias roulette.

```
model "fixtures/tiny-lm"
model "org/local-lm"
use auto          # keeps prior spark.toml / model line (no pick)
```

**`use auto`** — keeps the **prior** configured model (`spark.toml` or an
earlier `model` / `use` line). Dry-run prints
`[model] prior <id> (no alias pick)`. It does **not** invent `fast` /
`code` from task text. Prefer an explicit `model "…"` line.
See [AI_PLAYBOOKS.md](AI_PLAYBOOKS.md); goldens: `make test-ai-playbooks`.

Optional **`spark.toml`** (`model = "…"`) is read by the **bootstrap**
VM on startup; `./spark` (GAS) still needs a `model`/`use` line in the file.

## Statements

### `model analyze` / `compare` / `improve` / `train` / `status` / `plan`

Analyze and compare reachable models, propose improvements, **train**
real jobs (weights/adapters/checkpoints), poll **status**, or export an
optional markdown **plan**. Dry-run uses **fixtures only** — no GPU and
no network. **`model build` is an alias for `model train`** (not a
blueprint file).

Training methodology: [MODEL_TRAINING.md](MODEL_TRAINING.md).
Eval helpers: [MODEL_ANALYSIS.md](MODEL_ANALYSIS.md).

```
model analyze "fixtures/tiny-lm" -> report
model analyze all -> catalog_report

model compare ["fixtures/tiny-lm"] on suite "examples/eval_suite.json" -> comparison

model improve from report prefer quality -> blueprint
# prefer: quality | speed | cost | local

model plan blueprint into "out/better-model.md"   # markdown only

model train dataset "examples/fixtures/train/dataset.jsonl" base "fixture-base" out "out/train/job-dry-001" backend "http" method "spark_distill_cpu" -> job
model build -> job                               # same as train
model status "job-dry-001" -> status             # polls that job id
```

Optional **`method "…"`** selects the training algorithm
(`spark_distill_cpu` | `spark_pref_pack` | `spark_playbook_fit` |
`spark_faq_index` | `spark_reply_pack`).
**`spark_reply_pack`** overlays text + spoken replies on a base that
has no voice (or locks major behaviors). Inventable facts require
`sot_ref` — missing SoT fails loud; the pack never fabricates.
Default when omitted: `spark_distill_cpu` (env `SPARK_TRAIN_METHOD`
override). Live GAS passes the statement via
`./spark-train-http --spark-line`; status uses the **quoted** job id
(never a hardcoded `job-dry-001`). GAS-first — no SPARK_BC opcode yet
(see [SPARK_BC.md](SPARK_BC.md)).

**Backends:** `http` (default MVP companion `./spark-train-http`),
`local-yield` (optional allowlisted `train@` unit), `huggingface`
(reserved — not wired). Env: `SPARK_TRAIN_BACKEND`, `SPARK_TRAIN_URL`,
optional `SPARK_TRAIN_TOKEN`. See [MODEL_TRAINING.md](MODEL_TRAINING.md).

### `head abstain` / `train` / `attach` / `ask`

Decode-layer abstain / IDK gating for **local** models (and dry stubs).
Companion `./spark-abstain`. Design: [ABSTAIN_HEADS.md](ABSTAIN_HEADS.md).

```
head abstain internal model "path" weights "out/heads/abstain.pt" threshold 0.7 idk "I don't know." -> gate
head abstain external model "path" weights "out/heads/ext.pt" threshold 0.7 -> gate
head train dataset "examples/fixtures/abstain/labels.jsonl" kind internal out "out/heads/abstain.pt" hidden_dim 64 -> job
# Prefer dim-matched export (see ABSTAIN_HEADS.md):
# head train dataset "examples/fixtures/abstain/labels_exported.jsonl" …
#   kind internal out "out/heads/abstain.pt" hidden_dim 16 -> job
head attach model "path" weights "out/heads/abstain.pt" out "out/heads/manifest.json" -> attach
head ask "Who is the mayor of Springfield?" -> answer
```

SELECT before SAMPLE: if `p(abstain) ≥ threshold` (or entropy/margin
trip) → emit `idk` and halt. Internal = probe registered with a frozen
backbone; external = sidecar on exported hiddens/logprobs. Prefer
`./spark-abstain --live export` then train so `hidden_dim` matches the
backbone. Inventable prices/IDs: SoT / HTTP / `expect` **before** free
generate. Flagship: `examples/no_invent.spark` (also
`examples/head_ask_inventable_verify.spark`). Not LoRA.
Dry-run = fixtures only. Never `auto`/`code`/`fast`. Full runbook:
[ABSTAIN_HEADS.md](ABSTAIN_HEADS.md).

**“All models”** = all reachable configured model ids + discovered local
vLLM endpoints (read-only) — **not** every model in existence. Catalog:
`data/model-catalog.jsonl`. Public gateway probes need a probe
credential; 401 → credential unavailable (no invented routing).

**Why shape (mandatory for analyze/compare/improve):** metrics
(latency, tokens/s, quality proxy, tool JSON %), failure_modes,
concrete `reasons[]`, risks on improve/plan.

Examples: `examples/model_train.spark`, `examples/model_improve.spark`.

### `ask` / `generate` / `?`

**Bootstrap only:** `{topic}` in the quoted prompt resolves `let topic "…"`
bindings (fail loud if missing). GAS dry-run matches fixtures on prompt
substrings (e.g. `Summarize:` still hits the summary stub even with `{doc}`).

**Dry-run** (`--dry-run`): offline heuristic replies (no network).

**Live** (`--live`): OpenAI-compatible `POST /v1/chat/completions` via
companion `./spark-ask-http` → `AI_GATEWAY_URL`. See
[ASK_LIVE.md](ASK_LIVE.md). Model id comes from the prior explicit
`model` / `use` line (HF id / path / configured name). `--model auto`
is rejected. Prefer `SPARK_GATEWAY_KEY`;
`OPENAI_API_KEY` is wire-compat only. Public tunnel uses a probe credential; HTTP 401 → credential unavailable (no invented routing).
`make test` never hits the network; `make test-ask-gateway` is offline
`--dry` on the companion. Inventable live/dry prompts **IDK** unless
`--sot-ok` (see [ASK_LIVE.md](ASK_LIVE.md)).

**Accounting:** dry-run prints
`[accounting] latency_ms=0 … note=dry-run` (zeros; never invents
tokens). Live `./spark-ask-http` prints wall-clock `latency_ms`
(`CLOCK_MONOTONIC`) plus gateway `usage` when present, appends
`/tmp/spark-ask-account.jsonl` (or `--account-file` /
`SPARK_ACCOUNT_FILE`). End of a live `./spark --live` run prints
`[accounting-run]` via `./spark-ask-http --rollup`. See
[ASK_LIVE.md](ASK_LIVE.md).

### `ask probe` / `gateway probe`

Dry gateway probe credential check (no network under `--dry-run`):

```
ask probe -> info
gateway probe -> info
```

Companion `./spark-ask-probe --dry|--live`. On miss/401 → exit **4**,
print credential unavailable — never invent routing, never ask to mint
PAT, never reuse `cursor-ide`.

### `embed` / `retrieve` (first-class)

Gateway-shaped RAG surface. Dry-run uses fixtures under
`examples/fixtures/rag/` (same JSON as `bootstrap/dry_rag.c`).
Live forks `./spark-rag-http`.

**`embed`** — OpenAI-compatible `POST /v1/embeddings` via `AI_GATEWAY_URL`.
Default alias **`embed-rag`** (TEI). Optional `embed`.

```
embed "Spark is a language for AI workflows" -> vec
embed "…" model embed-rag -> vec
embed "…" model embed -> vec
```

**`retrieve`** — rag-gateway `POST /v1/retrieve` with project + audience.
Default project **`docs`**, audience **`operator`**, `top_k` **8**.
Operator/cursor responses may include gateway **`crag`** fields
(grade/retry) — Spark does **not** re-implement CRAG in-process.
Compose with `ask` when you want an answer grounded on hits:

```
retrieve "how does dry-run work" from project "docs" -> hits
retrieve "…" from project "docs" audience "operator" top_k 4 -> hits
ask "Answer using only: {hits}" -> reply
```

Dry-run: offline; `make test` / `make test-rag-gateway` never dial.
Live: `./spark --live` + `AI_GATEWAY_URL` / `SPARK_GATEWAY_KEY` for
`embed`; `RAG_GATEWAY_URL` (default `:4620`) +
`RAG_GATEWAY_API_KEY` or `SPARK_GATEWAY_KEY` for `retrieve`.
Prefer gateway keys — `OPENAI_API_KEY` is wire-compat only.

### `shell` / `run` (escape hatch — P0)

Call the host from `.spark`, and (design) embed `.spark` from a host
language. Closed DSLs die without this.

```
shell "echo hello" -> out
run "python" "-c" "print(1)" -> out
```

| Mode | Behavior |
|------|----------|
| **Dry-run** | **Never** execs. Allowlist `echo` / `true` / `false` → fixture stdout (`[shell] dry …`). Anything else → fail loud. `--allow-shell` is a no-op here. |
| **Live** | `./spark --live --allow-shell` forks `./spark-shell`, which `execve`s the resolved allowlisted binary (`/bin/echo` etc.). **Not** `system()`, **not** `/bin/sh -c`. Live without `--allow-shell` fails loud. Path / metacharacters / `rm` refused. |
| **Host embed** | **Shipped (Python, JS, C).** `from sparklang import run`; `require('./js/sparklang')`; `spark_run_path()` in `host/c/sparklang.h`. Dry-run default, `--live` opt-in. `./spark --embed` JSON handshake. |

```python
from sparklang import run

r = run("examples/hello.spark")          # dry-run default
print(r.stdout, r.returncode)
r = run('print "from host"\n')         # inline source → temp .spark
# r = run("examples/ask_live.spark", live=True)  # opt-in
```

```bash
PYTHONPATH=python python -m sparklang examples/hello.spark
node examples/js/host_embed.js
make examples/c/host_embed && ./examples/c/host_embed
./spark --embed   # {"api":"python,js,c",…}
make test-host-embed
make test-shell   # live --allow-shell argv execve
```

See [ADOPTION_BAR.md](ADOPTION_BAR.md). Examples: `examples/shell_escape.spark`
(from `.spark` → host), `examples/shell_refuse.spark` (fail loud),
`examples/python/host_embed.py`, `examples/js/host_embed.js`,
`examples/c/host_embed.c` (host → `.spark`).

### `http get` / `http post` (shipped)

Generic HTTP client ops — **not** Bifrost-specific and **not**
`engine fetch` `file://`. Dry-run never dials the network.

```
http get "https://example.com/" fixture "examples/fixtures/http/get_ok.json" timeout 5 -> resp
http post "https://example.com/api" body "{\"ping\":true}" fixture "examples/fixtures/http/post_ok.json" timeout 5 -> resp
http get "https://example.com/" bearer "TOKEN" retries 2 backoff 100 fixture "examples/fixtures/http/get_ok.json" timeout 5 -> resp
http get "https://httpbin.org/headers" header "X-Spark-Test: auth-retries" timeout 15 -> resp
```

| Clause | Meaning |
|--------|---------|
| `timeout N` | Seconds (default **30**, range 1–600). Live curl `-m`. |
| `bearer "TOKEN"` | Live: `Authorization: Bearer TOKEN`. Dry: logged as `auth=bearer` (token never printed). |
| `header "Name: value"` | Live: one extra curl `-H`. Conflict with `bearer` if Name is `Authorization` → fail loud. |
| `retries N` | Extra attempts after the first (0–8, default **0**). |
| `backoff MS` | Base delay ms between retries (0–60000). Default **100** when `retries > 0` and backoff omitted. Doubles each retry. |

**Live retries only on:**

- curl exit **7**, **28**, **35**, **52**, **56** (connect / timeout / SSL / empty / recv)
- HTTP **408**, **429**, **500**, **502**, **503**, **504**

No retry on 401/403/404 or other 4xx. Final non-2xx/3xx → exit **1**.

| Mode | Behavior |
|------|----------|
| **Dry-run** | **No network.** Requires `fixture "…"` **or** a `file://…` / `examples/fixtures/http/…` URL. **fopen** that path; missing file → fail loud. Bound value = fixture bytes (no invented status). `timeout` / `bearer` / `header` / `retries` / `backoff` are accepted and recorded; they do not dial. |
| **Live** (`./spark --live`) | Real HTTP via companion `./spark-http` (curl). Needs `http://` or `https://`. Auth headers and retries apply. `fixture` is ignored for the body. |

**Shipped:** get, post, timeout, bearer, header, retries, backoff, dry fixture files, live curl.

Example (dry): `examples/http_get.spark`, `examples/http_get_auth.spark`.
Live opt-in: `examples/http_get_live.spark`,
`examples/http_get_auth_live.spark`,
`examples/http_get_retries_live.spark`, or
`./spark-http --live --get --url https://example.com/ --timeout 10`.
Gate: `make test-http` (live SKIP unless `SPARK_HTTP_LIVE=1`).

### `extract`

Pulls typed fields out of text into JSON, validated on dry-run.
The inline schema declares the fields: a field is required unless its
name ends in `?`. Types are `string`, `int`, `float`, `bool`.

```
extract Person {
  name: string
  age: int
  email?: string
} from "Ada Lovelace was born in 1815"
  fixture "examples/fixtures/extract/person.json" -> person
```

Run it: `./spark --dry-run examples/extract_person.spark`.

`fixture "PATH"` names the JSON file that dry-run reads. Dry-run never
calls a model and never invents a value, so the clause is required:
without it, or with a path that does not exist, the run stops with a
non-zero exit.

Validation checks that every required field is present and that every
present field — required or optional — has its declared type. `float`
accepts an int (`3` is a valid float); `int` does not accept `3.5`, and
`bool` does not accept `0`/`1`. Only top-level keys count, so a nested
`{"address": {"age": 36}}` does not satisfy a top-level `age`. Extra
keys the schema does not mention are allowed and passed through.

A violation prints each problem and exits non-zero — nothing is bound
and nothing is printed:

```
$ ./spark --dry-run examples/extract_bad.spark ; echo $?
error: extract Person: field age expected int, fixture has string
error: extract Person did not validate against .../person_bad_type.json
1
```

**Live** (`./spark --live` / `./spark-extract --live`): model-backed
JSON extract via `./spark-ask-http`. Requires `from "TEXT"` and an
explicit `--model` (or `SPARK_MODEL`; `auto` refused). Validates the
reply against the schema; on a miss, retries with the validation
errors in the prompt (`--retries N`, default **2**, or a `retries N`
clause). Offline proof: `--stub-file PATH` (JSONL of canned replies).

```bash
./spark-extract --live --stmt-file /tmp/xt.txt --model fast --retries 2
./spark-extract --live --stmt-file /tmp/xt.txt --model fixtures/tiny-lm \
  --stub-file examples/fixtures/extract/stub_retry.jsonl
```

Examples: `examples/extract_person.spark` (valid dry),
`examples/extract_bad.spark` (type mismatch),
`examples/extract_live.spark` (live + retries). Gate: `make test-extract`
(includes stub retry cases).

### `expect` (pass/fail)

Assert a **bound** name against a literal or a fixture file. Pass =
exit **0**; fail = exit **1** with the reason. This is the dry-run CI
shape — not `model compare` picking aliases.

```
let answer "Ada Lovelace"
expect equal answer "Ada Lovelace"
expect contains answer "Lovelace"
expect equal answer fixture "examples/fixtures/eval/want_name.txt"
```

| Form | Behavior |
|------|----------|
| `expect equal NAME "…" ` | Exact string match |
| `expect contains NAME "…" ` | Substring match |
| `expect equal NAME fixture "PATH"` | Exact match to file bytes (trailing NL trimmed) |
| `expect contains NAME fixture "PATH"` | Substring match against file bytes |

Missing binding, missing fixture, or mismatch → non-zero exit (no
invented want). Gate: `make test-expect`.

Examples: `examples/expect_pass.spark` (exit 0),
`examples/expect_fail.spark` (exit 1),
`examples/expect_miss_fixture.spark` (exit 1).
Flagship train→status→expect: `examples/train_eval.spark` (exit 0) and
`examples/train_eval_fail.spark` (exit 1).

**Not shipped:** regex `match`, streaming ask assertions.

### `classify` (first-class)

Single-label (default) or `multi`:

```
classify Intent { support, sales, spam }
  from "My account is locked"
  min_confidence 0.7
  -> intent

classify multi Tags { support, sales, spam }
  from message -> tags
```

Dry-run returns `{ label, confidence, reasons }`. Invalid labels fail loud.

### `listen` / `speak` / `voice` (first-class)

Provider-agnostic STT/TTS primitives. Extended voice surface
(review / code / copy / model / pstn): [VOICE.md](VOICE.md).

```
listen "input.wav" -> transcript
speak "Hello" -> "out.wav"
speak with model brand_voice

voice {
  listen -> user
  classify Intent { support, sales } from user -> intent
  ask "Reply helpfully to: {user}" -> reply
  speak reply
}

voice review "clip.wav" -> report
voice code request "listen classify speak" -> artifact
voice copy from "src.wav" to my_voice -> model_path
voice model write my_voice spec { ... } -> path
voice model load my_voice -> model
voice pstn status
voice pstn dial "+15555550100" -> call   # OFF by default
```

Dry-run: `listen`/`speak` use stub transcript + minimal WAV write
(`speak … -> "path"` honored). `--live` forks `./spark-stt-tts`
(real WAV/mic/synth/local whisper; vendor HTTP OFF unless
`SPARK_STT_NET` / `SPARK_TTS_NET` / `SPARK_SPEECH_NET=1` —
see [VOICE.md](VOICE.md)).
`voice review` **byte-parses** real RIFF/WAVE (not invented metrics);
`voice code|copy|model` write real artifacts under `out/`.
PSTN never places in `--dry-run` / `make test` (companion gated OFF).

### `pipeline`

```
pipeline {
  ask "Summarize: {doc}" -> summary
  | ask "Translate to Spanish: {summary}" -> es
}
```

Compose with classify/listen/speak the same way. Include shared steps
from `lib/pipeline.spark` via bootstrap `include "lib/pipeline.spark"`.

### `include "path"` (bootstrap VM)

Inlines another `.spark` file at the statement site. Cycle-safe.
Not implemented in GAS `./spark` yet — self-host lane B only.

```
include "lib/ai.spark"
? "Hello" -> reply
```

### `tool` / `with tools`

```
tool weather(city: string) -> string { "stub:local" }

with tools [weather] {
  ask "Weather in DSM?" -> answer
}
```

`tool` registers a name. `with tools [name,…]` **activates** that
registration for the following block (`}` clears scope). Dry-run `ask`
inside an active scope returns `[tool:<name>] stub:local` (not a
generic model string). Fail loud if `with tools` lacks `[…]` or no
prior `tool` registration matching the list.
### `let` / `print` / `set`

Bindings and output for reviewable scripts.

### `review` / `builder` / `implement` (first-class)

Review AI-written or web-context code **without executing it**. Builder
picks a target level and codegen; implement writes artifacts.

```
review path "examples/fixtures/sample.js" -> report
review url "file://examples/fixtures/sample.js" -> report
review url "https://example.com/app.js" -> report   # needs --allow-net
review text "function x(){ eval(y); }" -> report

builder prefer lower request "add classify Intent and wire voice turn" -> patch
# prefer: lower | higher | auto

implement patch into "out/program.spark"
```

**Report shape:**
`{ issues[], complexity, suggested_level: lower|mid|higher, rationale }`
— `review url` adds `op`, `source`, `url`, `bytes`, `fetched`, `eval:false`.

**Levels**
- `lower` — emit/extend Spark that maps to asm VM ops (or `.s` later)
- `mid` — stay on Spark / C-like surface
- `higher` — Python/JS-ish **suggestion layer** (`out/program.py.txt`) — does **not** replace the asm VM

**Safety:** `review url` never `eval`s. Policy **A+B** (owner 2026-08-31):
**B** default — `file://` or bare path → open/read + static scan (no
network). **A** opt-in — remote `http(s)://` + `--allow-net` → curl fetch
+ same static scan. Without `--allow-net`, remote URLs exit non-zero with
a clear error instructing `--allow-net` — never dial, never a silent stub,
never a permanent QUESTION menu.

Honest framing: implement = codegen into `.spark` / suggestion files the
asm VM can re-run or humans can read — not magical self-modifying Linux apps.

## IDE core (`ide`)

Asm: `asm/ide_ops.s`. Examples: `examples/ide_hello.spark`,
`examples/ide_ask.spark`, `examples/ide_show.spark`,
`examples/ide_run_show.spark`, `examples/ide_ask_show.spark`,
`examples/ide_save_reopen.spark`, `examples/ide_new_chain.spark`,
`examples/ide_buffer_forms.spark`, `examples/ide_save_forms.spark`,
`examples/ide_show_forms.spark`, `examples/ide_ask_forms.spark`, `examples/ide_new_forms.spark`, `examples/ide_run_forms.spark`,
`examples/ide_dirty_status.spark`.
Verified under `--dry-run` / `make test`.

```
ide new "out/ide/ide_new_blank.spark"
ide buffer -> shown
ide save -> saved
ide open "out/ide/ide_new_blank.spark" -> opened
ide buffer -> shown
```

| Op | Notes |
|----|-------|
| `new` | Clear in-memory buffer; optional `"path"` |
| `open "path"` | Read file into buffer |
| `save` / `save "path"` | Write buffer (`out/ide/` as needed) |
| `buffer` / `buffer -> shown` | Terminal dump; bind optional (not `show`) |
| `run` | Flush to path or `out/ide/buffer.spark`; fork `./spark` |
| `ask` [`"instruction"`] | Real `ask_run_prompt` + AI strip |
| `show` [`"path.ppm"`] | After paint: `engine_window_show` / live `./spark-engine-show` |

Parent `--dry-run` → child `--dry-run`. Parent `--live` → child `--live`.
Unknown op / empty `run` → non-zero exit. No Electron/PyQt product surface.
Exports `ide_buf` / `ide_buf_len` / `ide_dirty`; calls
`ide_paint_bind` after mutate. Buffer edit (`ide new`) sets dirty →
status strip appends `*` (`out/ide/status_dirty.txt`); `open`/`save`
clear dirty. Proven chain: `examples/ide_new_chain.spark` (new →
buffer → save 0-byte → open → buffer). Proven buffer forms:
`examples/ide_buffer_forms.spark` (bare + `-> shown`). Proven save
forms: `examples/ide_save_forms.spark` (quoted path + bare). Proven
show forms: `examples/ide_show_forms.spark` (bare + quoted `.ppm`).
Proven ask forms: `examples/ide_ask_forms.spark` (bare + quoted
instruction). Proven new forms: `examples/ide_new_forms.spark` (bare
+ quoted path). Proven run forms: `examples/ide_run_forms.spark` (bare
+ `-> ran`). Keymap `n`→new is **not** proven. See [IDE.md](IDE.md).

## IDE keymap (`ide keys` / `ide key`)

Asm: `asm/ide_keys.s`. Example: `examples/ide_keys.spark`.
Script fixture: `examples/fixtures/ide/cmds.txt`.
Verified under `--dry-run` (`rc=0`). Open/save use shared `ide_buf`.
Open paints `out/ide/editor.ppm`; `show`/`w` reuses engine window.

```
ide keys "examples/fixtures/ide/cmds.txt"
ide key open "examples/hello.spark"
ide key show
ide key save
ide key run
ide key quit
```

Script tokens (proven only): `q`/`quit`, `s`/`save`, `r`/`run`,
`o path`/`open path`, `w`/`show`. Save token proof:
`examples/ide_keys_save.spark` + `examples/fixtures/ide/cmds_save.txt`
(`s` → `"cmd":"save"` under dry-run; no write). Run token proof:
`examples/ide_keys_run.spark` + `examples/fixtures/ide/cmds_run.txt`
(`r` → `"cmd":"run"` under dry-run; no fork). Quit token proof:
`examples/ide_keys_quit.spark` + `examples/fixtures/ide/cmds_quit.txt`
(`q` → `"cmd":"quit"` under dry-run; ends loop). Show token proof:
`examples/ide_keys_show.spark` + `examples/fixtures/ide/cmds_show.txt`
(`w` → `"cmd":"show"` under dry-run; validates PPM). Open token proof:
`examples/ide_keys_open.spark` + `examples/fixtures/ide/cmds_open.txt`
(`o path` → `"cmd":"open"` under dry-run; paints PPM). Long-form proof:
`examples/ide_keys_long.spark` + `examples/fixtures/ide/cmds_long.txt`
(`open` / `quit` aliases of `o` / `q`). Also
`examples/ide_keys_long_srs.spark` +
`examples/fixtures/ide/cmds_long_srs.txt` (`save` / `run` / `show`).
Unknown token proof: `examples/ide_keys_unknown.spark` +
`examples/fixtures/ide/cmds_unknown.txt` (`ok`:false).
Fail-loud: `examples/ide_save_nopath.spark` (no path);
`examples/ide_run_nobuf.spark` (empty buffer);
`examples/ide_ask_nobuf.spark` (empty buffer);
`examples/ide_open_nopath.spark` (needs path).
Proven binds: `examples/ide_bind_forms.spark` (`-> opened` /
`-> saved`). Proven status path: `examples/ide_status_path.spark`.
Proven ask bind: `examples/ide_ask_bind.spark` (`print reply` →
Gravity). Fail-loud open miss: `examples/ide_open_miss.spark`.
Fail-loud show miss: `examples/ide_show_miss.spark`.
Fail-loud show not-PPM: `examples/ide_show_notppm.spark`.
Fail-loud keys miss: `examples/ide_keys_miss.spark`.
Proven run bind: `examples/ide_run_bind.spark` (`print ran` →
op JSON). Proven new bind: `examples/ide_new_bind.spark`
(`print created` → op JSON). Proven quoted ask bind:
`examples/ide_ask_quote_bind.spark` (`print reply` → Gravity).
Fail-loud `ide key` bad token: `examples/ide_key_bad.spark`.
Proven buffer bind: `examples/ide_buffer_bind.spark`
(`print dump` → op JSON). Proven bare `ide keys`:
`examples/ide_keys_bare.spark` (default cmds.txt). Soft-fail
`ide key open` nopath: `examples/ide_key_open_nopath.spark`
(`ok`:false, rc=0). Proven open bind: `examples/ide_open_bind.spark`
(`print opened` → op JSON). Proven save bind:
`examples/ide_save_bind.spark` (`print saved` → op JSON). Proven
status * after new: `examples/ide_status_new_star.spark`.
Proven bare `ide key quit`: `examples/ide_key_quit_alone.spark`.
Proven status clear after save: `examples/ide_status_clear.spark`.
Proven bare `ide key show`: `examples/ide_key_show_alone.spark`.
Dry-run: JSON traces (+ `out/ide/keys_trace.jsonl`); open still reads
+ paints; show dry-validates PPM; save/run do not write/fork. Dispatched
before core buffer ops. No mouse GUI. Paint wire
(`make test-ide-paint` → `out/ide/editor.ppm`) is **not** a `.spark`
statement — [IDE.md](IDE.md).

## Binary (any machine-level file)

First-class ops to **open and analyze binaries** (ELF shared objects,
kernel modules, firmware blobs). Default `./spark` stays **syscalls-only**.
ELF **headers** are parsed in **assembly** via `open`/`read`/`fstat`/`lseek`.
Dynsym filters and `objdump -d` windows are orchestrated by
`make spark-binary` → `./spark-binary-probe` (documented shell-out — not
a fake in-asm x86 decoder).

```
binary open "path/to/lib.so" -> bin
binary elf bin -> elf
binary disasm bin at offset 0x1000 length 64 -> ops
binary understand bin -> report
binary understand bin focus cuda|memory|uvm -> report

binary kernelmod "module.ko" -> report
binary firmware "blob.bin" -> report
```

**What “understand” / “disasm” write:** under
`out/decompile/<basename>/` — **every** ELF section, full contents
(no `.text`-only / no sampling / no “relevant sections” shortcut):

- `ALL_SECTIONS.contents` — `objdump -s -w` (full hex of **every** section)
- `ALL_SECTIONS.disasm` — `objdump -D -w` (disassemble **every** section;
  non-code still listed)
- `<section>.raw` — full raw bytes via `./spark-section-dump` (any size;
  checkpoint/resume with `--resume`; NOBITS → empty file)
- `lifted/` — C-like lift from `ALL_SECTIONS.disasm` via `./spark-lift`
  (`lifted_common.h`, per-section `.c`, `lifted.c` index)

Files **>32MiB** print a progress note and **continue** the full dump
(no gate, no silent partial). Asm forks `objdump`, `spark-section-dump`,
and `spark-lift`. Re-running understand when `ALL_SECTIONS.disasm` +
`lifted/lifted.c` already exist **skips** objdump/lift and only runs
`spark-section-dump --resume` (checkpoint). Dynsym export names for the
understand JSON come from `./spark-binary-probe --exports` (mmap) — never
the 64KiB asm file peek (that SIGSEGV'd when `e_shoff` sat past 64KiB,
e.g. ~96MiB `libcuda.so.1`).

**kernelmod:** ELF header when uncompressed; `.ko.zst` is noted as
compressed (not ELF until decompress). Never `rmmod` / rewrite.

**firmware:** size + magic + coarse limits — opaque ISA → no fake
instruction semantics.

Example: `examples/binary_any.spark` (fixtures).
CUDA drivers: `examples/binary_cuda_drivers.spark`.

```
./spark --dry-run examples/binary_any.spark
ls out/decompile/tiny_cuda_stub.so/lifted/
make spark-binary && ./spark-binary-probe --understand \
  /lib/x86_64-linux-gnu/libnvidia-ml.so.1 --focus memory
```

## Network

Local pcap analysis. Dry-run **never claims** a live sniff unless
`--allow-net-capture` is set **and** `CAP_NET_RAW` is available.

```
network capture probe -> info
network capture interface "lo" duration 5s -> pcap
network open "examples/fixtures/sample.pcap" -> pcap
network analyze pcap -> traffic_report
network explain traffic_report -> text
```

- **capture probe**: forks `./spark-net-capture --probe` — AF_PACKET
  socket attempt only; always `claimed:false`; JSON
  `cap_net_raw` / `ready`. No `--allow-net-capture` needed.
- **capture** without `--allow-net-capture`: `claimed:false`, loads
  fixture pcap so `analyze` still works.
- **capture** with `--allow-net-capture`: forks `./spark-net-capture`
  (AF_PACKET SOCK_RAW → classic pcap). Needs `CAP_NET_RAW`
  (`sudo setcap cap_net_raw,cap_net_admin+ep ./spark-net-capture`).
  CAP miss → exit **4**, `claimed:false` (never invents packets).
- **open**: real `open`/`read` of magic `0xa1b2c3d4`.
- **analyze**: DNS QNAME from pcap bytes after open. Without open → error.
- **explain**: plain-language summary of parsed bytes.

```
./spark --dry-run examples/network_analyze.spark
./spark --dry-run examples/network_capture.spark
./spark --dry-run examples/network_capture_probe.spark
./spark-net-capture --probe
./spark --dry-run --allow-net-capture examples/network_capture.spark
```

## Browser / MITM (language SoT)

`.spark` programs **are** the browser driver. Asm dispatch in
`asm/browser_ops.s` — not a Python stub.

### Canonical entrypoints (only these)

| Mode | Entry |
|------|--------|
| Dry (no display) | `./spark --dry-run examples/browser_main.spark` |
| Live product | `cd ../spark-browser && make run` → `./spark --live browser/run.spark` |
| Dry E2E | `make test-e2e-browser` (spark and/or spark-browser) |

Do **not** document `python3 -m spark_browser run` as the product
entry (`make run-host` = Qt debug only).

```
browser run "examples/browser_main.spark"
browser flags
browser goto "https://example.com/"
browser cdp status
browser cdp navigate "https://example.com/"
browser cdp evaluate "document.title"
browser cdp screenshot "out/browser/cdp-shot.png"
mitm ca-init
mitm ca-status
mitm ca-install
mitm enable
mitm smoke
mitm disable_quic on
mitm quic status
mitm quic smoke
mitm filter "example\\.com"
mitm har export "out/browser/session.har"
browser show "examples/fixtures/browser/engine_show.ppm"
browser engine render
engine fetch parse "file://examples/fixtures/engine/sample.html"
engine parse "engine/fixtures/hello.html"
engine paint fixture
js eval "1+1"
```

### Engine B (Spark asm — product render path)

Not Chromium / not Qt. Real ops only:

| Op | Behavior |
|----|----------|
| `engine fetch "…"` | `file://` / bare path always; `http://` needs `--allow-net` (asm socket); `https://` needs `--allow-net` → fork `./spark-engine-fetch-tls` (OpenSSL BIO). Body → `out/engine/body.bin` |
| `engine fetch parse "…"` | fetch then `engine parse "out/engine/body.bin"` |
| `engine parse "…"` | asm HTML tokenizer → `out/browser/engine/dom.json` |
| `engine css attach` | CSS subset (display + margin/`padding`/`width`/`height` px + cell `border-width` px + color/bg) → `css.json` |
| `engine layout` | DOM → SePaintBox[]; table-row equal cells + inline-block; **fail closed** without parse |
| `engine layout fixture` | layout selftest (no DOM; includes `border_cells` / `layout.table`) |
| `engine paint boxes` | layout boxes → `out/engine/pipeline.ppm` (cell borders + cell text); **fail closed** if 0 boxes |
| `engine paint fixture` | SePaintBox demo → `out/engine/paint_fixture.ppm` |
| `browser engine render` / `engine render` | layout→paint_boxes→show → `pipeline.ppm` (**fail closed** without DOM) |
| `engine show "….ppm"` / `browser show` | dry validates PPM + `show.json` (`display:false`); `--live` forks `./spark-engine-show --ppm PATH --hold 2000` (X11 PutImage; needs `DISPLAY`) |
| `js eval\|run\|console\|selftest` | phase-1 numbers/strings/`+`/unary `-`/`var` num/console.log — **not** full ES |
| `engine parse` + `<script>` | after parse, text children → `engine_js_eval` (tiny only; fail loud) |

Dry layout→pixels: `examples/engine_layout_render.spark` → `out/engine/layout.ppm`.
Full pipeline: `examples/engine_pipeline.spark` → `out/engine/pipeline.ppm`.
Table: `examples/engine_pipeline_table.spark`; fetch→parse→layout:
`examples/engine_fetch_parse_layout.spark`.

**Honesty:** not full CSS / not Google.com / not full ES / not Electron.
HTTPS TLS **not** in asm — OpenSSL BIO companion
`./spark-engine-fetch-tls` under `--allow-net` only. JS phase-1 only
(numbers/strings/`+`/unary `-`/`var` num/console.log).

**Live X11 (real window, not dry):**

```bash
make spark-engine-show
./spark --dry-run examples/engine_pipeline.spark   # paints pipeline.ppm
./spark --live examples/engine_pipeline.spark      # opens X11 from that PPM
./spark-engine-show --ppm out/engine/pipeline.ppm --hold 3000
```

Same dry/`--live` split: `examples/browser_show.spark`,
`examples/browser_engine_render.spark`. Dry tests never open X11.

- **browser run|open|start** — session under `out/browser/`
  (`session.json`). Dry-run never launches a GUI. Session JSON
  includes `disable_quic:false` by default (QUIC ON).
- **browser flags** — reports disable_quic default / override.
- **browser goto** — records navigation URL (requires session).
- **browser cdp** — CDP client to Qt `:9222`
  (`status|navigate|evaluate|screenshot`). Dry-run returns
  mocks (`claimed:false`, never dials). `--live` forks
  `./spark-browser-cdp` (Python in spark-browser). Screenshot
  optional path; default `out/browser/cdp-shot.png`.
- **mitm ca-init** — forks `./spark-mitm-ca --init` (RSA CA under
  `out/browser/ca/` + product `spark-browser/data/ca/`). Language
  SoT for MITM trust. Separate from the **encrypt-to-model** gateway
  (`crypto` / `encrypt` / `gateway` — see below).
- **mitm ca-status** — present/missing via helper `--status`.
- **mitm ca-install** — dry-run **plans only** (never auto-trust);
  `--live` forks `install-ca.sh` (NSS / optional `--system`).
- **mitm enable|disable|filter** — owner-local intercept
  (`mitm.json`). Dry-run session markers only. **`--live` enable**
  forks `./spark-mitm-h2 serve --daemon` (CONNECT h2/h1 + capture
  + HAR). Qt must **attach**, not start the forge.
- **mitm smoke** — forks `./spark-mitm-h2 --smoke` (HTTPS forge
  proof; Spark-owned, no GUI).
- **mitm disable_quic on|off** — optional Chromium `--disable-quic`
  (product default is QUIC ON; use on for TCP h2/h1-only MITM).
- **mitm quic status|listen|smoke|divert** — HTTP/3 lane; `smoke`
  forks `./spark-mitm-quic` (aioquic forge + SNI leaves). UDP MITM
  via divert→listen (CONNECT-UDP is honest 501 on Qt TCP proxy).
- **mitm har export** — writes a real HAR 1.2 file (byte-written).
  Requires `mitm enable`. Dry HAR is a synthetic single-entry from
  goto URL (valid 1.2); live multi-flow HAR comes from
  `./spark-mitm-h2` session dir (not from Qt).
- **browser gui** — only with `--live`; forks
  `./spark-browser-host` (Qt **attach-only** to Spark MITM on
  `:8877`). Dry-run → error. Shim defaults to Chromium
  `--enable-quic`. Optional `--disable-quic`. Debug: `--own-mitm`
  (not product).

```
./spark --dry-run examples/browser_ca.spark
./spark --dry-run examples/browser_h2.spark
./spark --dry-run examples/browser_quic.spark
./spark --dry-run examples/browser_main.spark
ls out/browser/ca/ca.pem out/browser/session.har
make test-e2e-browser
```

OS blueprint scaffold (`os generate` kind browser) remains for docs
layout; language ops above are the runtime SoT.

## Encrypt gateway (encrypt-to-model)

Off by default. When enabled, `ask` seals the prompt and sends a GCM
envelope to `./spark-enc-gateway`, which **decrypts inside the gateway
process** and only then calls Bifrost. Full docs:
[ENCRYPT_GATEWAY.md](ENCRYPT_GATEWAY.md).

```
crypto probe -> info
crypto backend openssl
crypto keygen -> key
encrypt gateway enable key
gateway encrypt on
encrypt seal text "secret" -> blob
encrypt open blob -> text
ask "..." -> reply
gateway encrypt off
```

`crypto backend af_alg` fails loud when `algif_aead` is blacklisted
(CVE-2026-31431). Default remains OpenSSL. See
[ENCRYPT_GATEWAY.md](ENCRYPT_GATEWAY.md).

```
./spark --dry-run examples/encrypt_gateway.spark
./spark --dry-run examples/crypto_probe.spark
./spark-enc-gateway self-test
./spark-enc-gateway probe
```

## CUDA

GPU ops are **pure x86_64 asm syscalls** in `asm/cuda_ops.s` — not NVML,
not a QUESTION. Runtime path:

1. `open` `/dev/nvidiactl`, `/dev/nvidia0`, `/dev/nvidia-uvm`
2. `ioctl` `NV_ESC_CHECK_VERSION_STR` (`0xc04846d2`) and
   `NV_ESC_CARD_INFO` (`0xc90046c8`) — numbers from
   `/usr/src/nvidia-*/common/inc/nv-ioctl-numbers.h` as data
3. Optional anonymous `mmap`/`munmap` path proof
4. Prefer compute on minor **0**; refuse reserved minors for
   prefer/compute when policy marks them off-limits

`fb_bytes` comes from `NV_ESC_CARD_INFO`. Prefer minor **0**.
Refuse `prefer gpu 2` when that device is reserved.

```
cuda probe -> info
cuda memstat -> stats
cuda prefer gpu 0
```

### `cuda pcie` / `pcie probe` (live sysfs)

**First-class hardware capability** in `asm/pcie_ops.s` (additive; does
not touch voice/browser asm). Reads live PCI link attrs only — never
invents Gen/width:

- `/sys/bus/pci/devices/<bdf>/current_link_speed`
- `current_link_width`, `max_link_speed`, `max_link_width`

Report fields per GPU: `bus_id`, `gen_current` / `gen_max`,
`width_current` / `width_max`, measured `speed_*_gts`, `downgraded`
(true when width or gen < max), `role` (`spark-prefer` for minor 0;
reserved roles for off-limits minors). Prefer-minor **0**; refuse
reserved GPU indices as Spark targets. No reboot. No claim that x16
is fixed.

```
cuda pcie -> report
pcie probe gpu 0 -> report
cuda pcie explain -> text
```

`explain` prints measured causes for a PCIe downgrade (riser /
bifurcation / seating / shared lanes) from live `/sys` data. Fixture
snapshot under `examples/fixtures/pcie/` documents sample sysfs;
runtime always reads live `/sys`. Example: `examples/cuda_pcie.spark`.

Optional companion `make spark-cuda` → `./spark-cuda-probe` remains for
NVML cross-checks; it is **not** required for `cuda` language ops.

### `memory pin`

Real `mmap` + `mlock` syscalls in `asm/cuda_ops.s`. Fail loud with
`errno=` on denial.

```
memory pin "buffer" size 1M -> buf
```

## `os` (OS blueprints for AI / agents)

Spark generates **OS blueprints + educational bootable stubs**, not a
host OS install. Output: `out/os/<name>/`. Bounds:
[OS_DESIGN.md](OS_DESIGN.md).

```
os design name "agentos" kind ai_agent -> blueprint
os design name "aikitchen" kind ai_runtime features [scheduler, model_router, sandbox, net] -> blueprint

os specify blueprint {
  target: x86_64
  memory_model: flat
  ai: { agent_runtime: true, model_slots: 4, tool_bus: true }
  drivers: [serial, framebuffer_stub, virtio_net_stub]
} -> spec

os generate spec into "out/os/agentos" -> tree
os build tree -> image
os explain blueprint -> text
```

Dry-run `os generate` copies `templates/os/ai_agent/` into the tree.
`os build` prints a dry-run assemble note (never `dd`, never reboot).
Example: `examples/os_agentos.spark`.

## Runtime flags

```
./spark --dry-run examples/hello.spark
./spark --dry-run examples/cuda_mem.spark
./spark --dry-run examples/cuda_pcie.spark
./spark --dry-run examples/binary_any.spark
./spark --dry-run examples/network_analyze.spark
./spark --dry-run --allow-net-capture examples/network_capture.spark
./spark --dry-run examples/browser_main.spark
./spark --live examples/ask_live.spark          # needs gateway
./spark --version
```

`--dry-run` is assembly (syscalls + forked helpers). Live packet capture
requires `--allow-net-capture` and `CAP_NET_RAW` on `./spark-net-capture`
(CAP miss → exit 4). Probe: `./spark-net-capture --probe`.
Live ask requires `--live` + `./spark-ask-http` + gateway env.
Optional model endpoint discovery: `make model-probe` (not in `make test`).
NVML companion `make spark-cuda` is optional cross-check only.
Browser dry E2E (no display): `make test-e2e-browser`.

## Errors

Human-readable: file open failures, usage, and (when live lands) schema /
classify mismatch messages. Dry-run uses heuristic stubs so CI needs no keys.

## Numeric expects (0.7)

| Form | Meaning |
|------|---------|
| `expect gte NAME $.path N` | JSON path ≥ N |
| `expect lte NAME $.path N` | JSON path ≤ N |
| `expect eq NAME $.path V` | JSON equality |
| `expect histogram_min NAME CLASS N` | class histogram floor |
| `expect score NAME $.path using "URL" >= N` | rubric score (dry fixture) |

`expect equal` / `expect contains` unchanged.
