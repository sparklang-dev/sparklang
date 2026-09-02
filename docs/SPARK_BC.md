# Spark bytecode ISA (Phase 0)

**Destination execution SoT** for the self-host lane: `.sparkbc`
runs on `bootstrap/bc_vm.c` (`spark-bootstrap --run-bc`).
Tree-walk `spark_vm_run_file` remains a **legacy bridge** until
later phases delete it.

This is **not** JVM, WASM, or CPython bytecode. Magic is Spark-only.

## Source of truth (no inventing)

Every opcode and stdout string traces to:

1. [`LANGUAGE.md`](LANGUAGE.md) — statement forms
2. [`examples/hello.spark`](../examples/hello.spark) — `model` / `ask` / `print`
3. GAS + C bootstrap dry-run stdout (same model/ask/→/print lines)
4. Existing dry fixtures in `bootstrap/vm.c` /
   `bootstrap/dry_ask.c` `spark_pick_ask_reply` (copied from
   `pick_ask_reply`; do not invent new reply prose)

**No inventing.** If a form is not in LANGUAGE.md, not in
`examples/hello.spark`, and not an existing dry helper string: do
**not** add an opcode, operand, or fixture. Phase 0 is only the
LANGUAGE statement starts already wired for hello, plus a VM
terminator.

## File layout (little-endian, packed, no padding)

```
offset 0  : 4 bytes magic  'S' 'P' 'B' 'C'
offset 4  : 1 byte  version 0x01
          : u16     nstrings
          : nstrings × { u16 nbytes; nbytes UTF-8 bytes }
          : u16     nconsts
          : nconsts × { u8 kind; u16 payload }
          : u32     ncode
          : ncode bytes (opcode + operands)
```

Version **must** be `0x01`. Other versions fail loud.
Bad magic / truncated section / unknown opcode / unknown const
kind / out-of-range index: **fail loud**, non-zero exit, no silent
skip.

### String pool

Quoted strings and identifiers from LANGUAGE / hello. No NUL in
the file; the loader appends `'\0'` for C. Phase 0 hello strings
are exactly:

| Index | Bytes | SoT |
|-------|-------|-----|
| 0 | `code` | `examples/hello.spark` `model code` |
| 1 | `Explain gravity in one sentence` | hello `ask "…"` |
| 2 | `text` | hello `-> text` / `print text` |

### Constant pool

Phase 0 kind **only**:

| Kind | Value | Payload |
|------|-------|---------|
| `STR` | `0` | u16 string-pool index |

No other kinds. Code operands are **u16 constant-pool indices**.
A `STR` const resolves to that string. hello.sparkbc uses three
`STR` consts (0→`"code"`, 1→prompt, 2→`"text"`).

### Code section

Stream of `u8 opcode` plus opcode-specific `u16le` const indices.
`HALT` has no operands. Execution starts at byte 0.

## Stack / frame model

**Frame (used in Phase 0):**

- `model_alias` — LANGUAGE `model <alias>` / hello `model code`
- named bindings — LANGUAGE `let` / `->` bind; hello `text`
- `last` — last ASK/LET value (same role as bootstrap `last_val`)

**Operand stack:** reserved. Phase 0 hello never pushes or pops.
No stack opcodes this phase (would be inventing).

## Opcode table (Phase 0 + Phase 4)

Mapped 1:1 to LANGUAGE.md statement starts. Voice merge keeps
`0x06 EXTRACT`, `0x07 PIPELINE`, `0x09 LISTEN`, `0x0a SPEAK`,
`0x0d VOICE`; engine/IDE `0x0e–0x1a`; review/browser/mitm
`0x1b–0x1f`. Tool/with use **0x20–0x22** (after mitm).

| Byte | Name | LANGUAGE.md | Operands (u16 const) | Dry-run stdout |
|------|------|-------------|----------------------|----------------|
| `0x00` | `HALT` | *VM-only* (not a keyword) | none | then `[spark] ok` |
| `0x01` | `MODEL` | `model` / `use` | alias | `[model] <alias>` |
| `0x02` | `ASK` | `ask` / `?` | prompt, bind | `[ask] <prompt>` / `  → <reply>` |
| `0x03` | `PRINT` | `print` | ident | `[print] <value>` |
| `0x04` | `LET` | `let` | name, value | `[let] <name> = <value>` |
| `0x05` | `CLASSIFY` | `classify` | from-text, bind | `[classify] <text>` / `  → <json>` |
| `0x06` | `EXTRACT` | `extract` | bind | `[extract] <json>` |
| `0x07` | `PIPELINE` | `pipeline` | none | `[pipeline] step` |
| `0x09` | `LISTEN` | `listen` | path, bind | `[listen] <transcript>` |
| `0x0a` | `SPEAK` | `speak` / `say` | text, path | `[speak] wrote <path>` |
| `0x0d` | `VOICE` | `voice` | none | `[voice] session …` |
| `0x0e`–`0x1a` | *engine/IDE* | `engine` / `ide` | per family | dry engine/IDE JSON |
| `0x1b`–`0x1f` | *review/browser/mitm* | `review` / `browser` / `mitm` | per family | dry review/browser/mitm |
| `0x20` | `TOOL` | `tool` | name | `[tool] registered <name>` |
| `0x21` | `WITH` | `with tools` | scope | `[with] {"op":"with_tools",…}` |
| `0x22` | `WITH_END` | `}` clears tools | none | *(no line; `vm.c` 1559–1562)* |
| `0x23` | `EMBED` | `embed` | text, bind | `[embed] <text>` / `  → <json>` |
| `0x24` | `RETRIEVE` | `retrieve` | query, bind | `[retrieve] <query>` / `  → <json>` |

`LET` is in the table so the ISA is not hello-only
(LANGUAGE.md `let` / `print` / `set`). hello.sparkbc does **not**
emit `LET`. Handler matches `bootstrap/vm.c` `op_let` (print +
bind + last). `set` is GAS-only in bootstrap — not an opcode here.

`EMBED` / `RETRIEVE` dry replies come from `bootstrap/dry_rag.c`
(same fixtures as `examples/fixtures/rag/`). Live GAS forks
`./spark-rag-http`.

`HALT` ends the program. Documented as VM-only; not a `.spark`
keyword.

### CLASSIFY (Phase 4 first family)

LANGUAGE form in `selfhost/fixtures/classify_dry.spark` (one line):

```
classify Intent { support, sales, spam } from "…" min_confidence 0.7 -> intent
classify multi Tags { support, sales, spam } from "…" -> tags
```

**Encoded operands (proven by dry-run SoT):** two `u16` const
indices, same shape as `ASK`:

1. **from-text** — the `from` STRING. GAS / `vm.c` `op_classify`
   uses only `extract_quote` of that string.
2. **bind** — IDENT after `->`. Bound value is the dry JSON.

**Not encoded (same as `vm.c`):** schema name (`Intent` / `Tags`),
`multi`, `{ support, sales, spam }` labels, `min_confidence`.
C compile still **parses** those tokens from classify_dry and
discards them. Do not invent a label-list operand.

Dry JSON is `spark_pick_classify` / `vm.c` `pick_classify` (copied
to `bootstrap/dry_classify.c`): buy/price → sales; broken/help/
support → support; spam → spam; else support. Strings are the
existing `DRY_SALES` / `DRY_SUPPORT` / `DRY_SPAM` fixtures. No new
prose.

GAS classify_dry body (compare SoT; banner may differ):

```
[model] fast
[classify] My account is locked
  → {"label":"support","confidence":0.91,"reasons":["dry-run"]}
[classify] Please help me buy a card
  → {"label":"sales","confidence":0.88,"reasons":["dry-run"]}
[print] {"label":"support","confidence":0.91,"reasons":["dry-run"]}
[print] {"label":"sales","confidence":0.88,"reasons":["dry-run"]}
[spark] ok
```

### TOOL / WITH / WITH_END (Phase 4 second family)

LANGUAGE form in `examples/tool_agent.spark` (same bytes as
`bootstrap/fixtures/tool_agent.spark`):

```
tool weather(city: string) -> string { "stub:local" }
with tools [weather] { ask "…" -> answer }
print answer
```

**Cited `vm.c` before encoding:**

- `op_tool` (~588) — name before `(`, print
  `[tool] registered %s`. Signature / `{ "stub:local" }` ignored.
- `op_with` (~608) — requires `tools`, prior registration, `[list]`;
  copies bytes between `[` and `]` into `tools_scope`; sets
  `tools_active = 1`; prints the existing JSON line.
- `}` (~1559–1562) — `tools_active = 0`; no stdout. That is
  `WITH_END` (not invented: LANGUAGE + this clear).
- `op_ask` (~468–471) — when `tools_active && tool_reg_len`: reply
  is the existing `[tool:NAME] stub:local` (not `pick_ask_reply`).

**Encoded operands (proven by that fixture + dry-run):**

1. `TOOL` — one `u16` const: tool **name** (`weather`).
2. `WITH` — one `u16` const: list text between `[` and `]`
   (`weather` for `[weather]`).
3. `WITH_END` — no operands.

**Not encoded (same as `vm.c`):** `(city: string)`, `-> string`,
`{ "stub:local" }` body. C compile parses those tokens and
discards them. Do not invent a signature operand.

GAS tool_agent body (compare SoT; banner may differ):

```
[model] code
[tool] registered weather
[with] {"op":"with_tools","tools":"weather","active":true}
[ask] What's the weather hint for Springfield?
  → [tool:weather] stub:local
[print] [tool:weather] stub:local
[spark] ok
```

## Dry-run semantics (stdout contract)

`--run-bc` is dry-run only (no network). Lines for model / ask /
arrow / print **must** be byte-identical to GAS
`./spark --dry-run examples/hello.spark` and bootstrap
`./spark-bootstrap --dry-run examples/hello.spark`.

GAS hello:

```
[spark] dry-run via assembly VM (machine code)
[model] code
[ask] Explain gravity in one sentence
  → Gravity pulls masses together.
[print] Gravity pulls masses together.
[spark] ok
```

Bytecode banner (allowed distinct line):

```
[spark] dry-run via bytecode VM
```

then the same `[model]` / `[ask]` / `  →` / `[print]` / `[spark] ok`.

ASK reply: `spark_pick_ask_reply` — `contains_ci` `"gravity"` →
`"Gravity pulls masses together."` (existing fixture; not invented).

PRINT of a bound name: `[print] <value>\n` (`vm.c` `op_print`).
Unbound name prints the ident (same as `vm.c`).
MODEL: `[model] <alias>\n`.

## hello.sparkbc hex / layout

Packer (encoding, not a compiler): `bootstrap/bc_pack_hello.c` +
`bootstrap/bc_write.c`. Reconstruct by packing the three strings
and four ops above, or `make spark-bc-pack-hello` and write the
golden. Phase 3 C `--compile` must emit the same bytes for hello.

Packed size of the golden: **79 bytes** (magic+ver 5 + nstrings 2 +
strings 2+4 + 2+31 + 2+4 + nconsts 2 + 3×3 + ncode 4 + 12 code).
Code section starts at **file offset 67**.

Code bytes:

```
01 00 00          MODEL const0
02 01 00 02 00    ASK   const1 const2
03 02 00          PRINT const2
00                HALT
```

## Out of scope (do not add)

include, `set`, live ask. Phase 3 C `--compile` lowers
hello/mini. Phase 4 adds classify, tool/with, extract, pipeline,
voice, engine/IDE, review/browser/mitm per table above.
Spark-hosted compiler is still out of scope. Later phases may grow
the ISA from LANGUAGE.md only.
