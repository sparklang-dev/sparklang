# Spark self-host path (A + B bootstrap + C)

**Destination:** Spark hosts Spark — VM and compiler authored as
`.spark` under `selfhost/`, not forever hand-written GAS.

**Execution SoT:** bytecode (`docs/SPARK_BC.md` / `bootstrap/bc_vm.c`)
is the destination runner. Tree-walk `spark_vm_run_file` is a
**legacy bridge** (Phase 4 deletes it). Hello already runs on B via
`--run-bc selfhost/fixtures/hello.sparkbc`.

**Owner pick (2026-08-31):** A with B bootstrap and C too.
Pivot record: `workspaces/reports/spark-vm-not-asm-pivot-20260831.md`.

This doc is the architecture SoT for the self-host lane. No vapor
calendar dates — stages advance when evidence on disk exists.

`selfhost/` is seeds + a C tokenize aid. It is **not** a full Spark
compiler, parser, or VM. Do not claim Stages 4–5 until those gates have
on-disk proof.

---

## Roles

| Lane | Owner tree | Job |
|------|------------|-----|
| **A** | `selfhost/` + this doc | Destination sources: lexer → parser → compiler/VM in Spark |
| **B** | `bootstrap/` or `vm/` (peer) | Thin **C** VM that runs a growing `.spark` subset |
| **C** | `sparkasm/` (peer) | Spark-native assembler (`.sasm` → ELF `.o` / `.bin`) |

**GAS `asm/*.s` → `./spark`:** disposable **scaffold** that still runs
today. Not forever authoring SoT. Delete/replace only when B (+ C where
needed) covers the same ops with proof.

Do **not** start a Rust/Python product VM. Do **not** deepen “GAS
forever.”

---

## Stages (evidence gates)

### Stage 0 — Scaffold + A seeds (current)

- `./spark` ELF from GAS still interprets language ops under
  `--dry-run` / `--live`.
- Language SoT: `docs/LANGUAGE.md`, `examples/*.spark`.
- A seeds under `selfhost/*.spark` dry-run on GAS; `lex.c` golden
  covers mini + ops fixtures.
- **Gate:** `make` + `./spark --dry-run examples/hello.spark` works;
  `make test-selfhost-lex` green.

### Stage 1 — Bootstrap B runs a subset  ← **REAL (advanced)**

- Thin C VM under `bootstrap/` → `spark-bootstrap` / `sparkc`.
- Dry-parity (proven): `model` / `ask` / `print` / `let` +
  `classify` / `extract` / `tool` / `with` / `listen` / `speak` /
  `pipeline` + `review path|text` + `voice` session +
  `browser run|goto|show|flags|render` + `mitm enable` +
  `engine fetch` `file://` / `parse` / `css attach` / `layout` /
  `paint boxes` / `show` / `render` (css.json + layout
  `box_count` 21 + pipeline.ppm vs GAS).
- **Live-only non-goals** (fail-loud; not this dry phase):
  `review url`, `browser gui` / `cdp`, `mitm` beyond enable,
  `engine` remote http(s) / `--live`, IDE chrome.
- **Gate met:** `make test-bootstrap` green (+ classify/tool/review/
  voice/browser/mitm/engine css/layout/paint/render parity vs
  `./spark` where wired).
- Stage 4–5 are **not** done (no Spark-hosted compiler; no
  default-`./spark` cutover).
- See `bootstrap/README.md`. Growing A lex seeds does **not** skip
  running self-host sources on B.

### Stage 2 — Assembler C replaces hand-GAS authoring  ← **REAL (phase-1)**

- `sparkasm` assembles Spark-asm IR → objects/binaries.
- Phase-1 proven: push/pop/push-imm/call/ret/jmp/cmp/test/jcc/add/sub/
  and/or/xor/shl/shr/lea/imul/neg/not/inc/dec/xchg/add-rr/sub-rr/cqo/cdqe/cmp-rr/sete/setl/movzbq/movsbq/shl-cl/sar/leave/mul/idiv/adc/sbb/rol/ror/stc/clc/rcl/rcr/bsf/bsr/std/cld/bt/bts/btr/btc/shld/shrd/cmovz/cmovnz/cmovl/cmovg/cmovle/cmovge/cmova/cmovb/cmovae/cmovbe/test-imm/`mov reg,reg`
  (GAS `6a 2a` / `48 99` / `48 98` / `48 39 f7` / `0f 94 c0` / `0f 9c c0` / `48 0f b6 f8` / `48 0f be f8` / `48 d3 e7` / `48 d1 ff` / `c9` / `48 f7 e6` / `48 f7 fe` / `48 11 f7` / `48 19 f7` / `48 d1 c7` / `48 d1 cf` / `f9` / `f8` / `48 d1 d7` / `48 d1 df` / `48 0f bc fe` / `48 0f bd fe` / `fd` / `fc` / `48 0f a3 ce` / `48 0f ab ce` / `48 0f b3 ce` / `48 0f bb ce` / `48 0f a4 f7 01` / `48 0f ac f7 01` / `48 0f 44 fe` / `48 0f 45 fe` / `48 0f 4c fe` / `48 0f 4f fe` / `48 0f 4e fe` / `48 0f 4d fe` / `48 0f 47 fe` / `48 0f 42 fe` / `48 0f 43 fe` / `48 0f 46 fe` / `48 f7 c7…` / `48 01 f7` / `48 29 f7` / `48 87 f7` / `48 f7 d7` / `48 ff c7` / `48 ff cf` / `48 89 f7`) — **not** full x86-64.
- **Gate met:** `make -C sparkasm test` green. Grow further as needed.

### Self-host sources run on B

- `selfhost/*.spark` (lexer, then parser, then compiler) execute on
  **B**, not only as docs.
- Lexer contract proven: tokens for `selfhost/fixtures/mini.spark`
  (and ops) match the seed goldens (see `selfhost/README.md`).
- **Gate (Phase 2 / Stage 3 entry):** B `--lex` matches
  `expected_*.tokens.jsonl`. Spark-hosted `lexer.spark` scan is
  **not** the golden producer (seed catalog only).

### Stage 3 — Lexer on B  ← **REAL (Phase 2)**

- `spark-bootstrap --lex` links `selfhost/lex.c` (same JSONL as
  `./selfhost/spark-lex`).
- **Gate met:** `make test-selfhost-lex` (17/17 via spark-lex **and**
  `--lex`).

### Stage 4 partial — C compile → SPARK_BC (Phases 3–5)

- `spark-bootstrap --compile file.spark -o out.sparkbc`
- C driver: `bootstrap/spark_parse.c` lowers LANGUAGE forms in
  `docs/SPARK_BC.md` (model/ask/print/let, classify, extract,
  pipeline, tool/with, listen/speak/voice, engine/IDE,
  review/browser/mitm). Fail loud on unknown stmts. `compile.spark`
  is still a seed.
- **Gates met:** `make test-sparkbc` (compile → `--run-bc` body equals
  GAS dry-run after banner for hello/mini/classify/extract/pipeline/
  tool/listen/speak + engine/IDE + review/browser/mitm fixtures).
  `make sparkbc-e2e` (TRAIN→STEP→TRAIN_STATUS: compile → dump →
  `--run-bc` dry → `ARTIFACT`; not SGD; weights follow-on).
  `make test-bc-emit` (bc_vm ↔ spark-bc-emit parity on same `.sparkbc`
  goldens).
- `--dry-run` tries compile+`bc_vm` first; on compile failure falls
  back to tree-walk `vm.c`. Tree-walk handlers kept for parity.
- **Not done:** Spark-hosted compiler; full tree-walk deletion;
  `include`/`builder`/`implement`/`model analyze` on BC; Stage 5/6.

### Stage 4 — Spark compiles Spark (full)  ← **NOT STARTED**

- Self-host compiler emits IR or objects (via C assembler / later
  Spark-hosted assemble).
- Scaffold GAS tree shrinks; product path is A-on-B (+ C).
- **Gate:** rebuild a known ELF or bytecode from `selfhost/` sources
  without editing GAS by hand.
- Phase 0: bytecode VM runs `hello.sparkbc` via `--run-bc`.
- Phase 3: C `--compile` is a bootstrap, not Stage 4 complete.
- Parser/grammar `.spark` files are catalogs only.

### Stage 5 — Kick the ladder  ← **NOT STARTED**

- Default `./spark` (or successor name) is B/self-host built, not
  `as`+`ld` of `asm/spark.s`.
- GAS retained only as archaeological / comparison until removed.
- **Gate:** owner cutover after Stage 4 proof — not earlier.
- `scripts/spark-bc` exists (Phase 6 wrapper); default `./spark` stays
  GAS. SPARK_BC → ELF via `spark-bc-emit` + `sparkasm` is proven
  (`make test-bc-emit`), not the product default.

### Stage 6 — downloads / product default  ← **NOT STARTED**

- `make spark` remains the GAS ELF. Do not default downloads to BC.

---

## What A owns now

| Path | Role |
|------|------|
| `selfhost/README.md` | Today vs goal; what dry-runs on GAS |
| `selfhost/token_kinds.spark` | Token kind catalog (dry-run) |
| `selfhost/lexer.spark` | Lexer algorithm seed (dry-run) |
| `selfhost/grammar.spark` | Statement grammar catalog (dry-run) |
| `selfhost/parser.spark` | Parser/AST plan seed (dry-run) |
| `selfhost/fixtures/mini.spark` | Tiny program for lex golden |
| `selfhost/fixtures/ops.spark` | Richer: PIPE, review path, NUMBER |
| `selfhost/fixtures/bootstrap_ops.spark` | Stage 1 B: tool/with/extract/listen/speak/pipeline |
| `selfhost/fixtures/review_voice.spark` | review path/text + voice{listen/speak} |
| `selfhost/fixtures/browser_dry.spark` | browser run/goto + mitm enable |
| `selfhost/fixtures/ide_dry.spark` | ide open/run/ask/show |
| `selfhost/fixtures/classify_dry.spark` | model + classify (+ multi) + print |
| `selfhost/fixtures/let_dry.spark` | model + let + print (`let` KEYWORD) |
| `selfhost/fixtures/ask_dry.spark` | model + ask + generate + print |
| `selfhost/fixtures/engine_dry.spark` | engine fetch/parse/css/layout (B Stage 1) |
| `selfhost/fixtures/ide_keys_dry.spark` | ide keys / ide key open|show|save|run|quit |
| `selfhost/fixtures/binary_dry.spark` | binary open/elf/disasm/understand/kernelmod/firmware |
| `selfhost/fixtures/network_dry.spark` | network capture/open/analyze/explain |
| `selfhost/fixtures/encrypt_dry.spark` | crypto/encrypt/gateway seal path |
| `selfhost/fixtures/cuda_dry.spark` | cuda probe/memstat/prefer + memory pin |
| `selfhost/fixtures/os_dry.spark` | os design/specify/generate/build/explain |
| `selfhost/fixtures/pcie_dry.spark` | cuda pcie / pcie probe / pcie explain |
| `selfhost/fixtures/hello.sparkbc` | Phase 0 golden — hello.spark on bc_vm |
| `selfhost/lex.c` | **Real** byte lexer (aid until Spark lexer on B) |
| `selfhost/expected_*.tokens.jsonl` | Goldens for `test-selfhost-lex` |
| `make selfhost-lex` / `make test-selfhost-lex` | Build + golden + dry-runs |

**Not claimed:** full parser implementation, or a complete compiler
in Spark. Phase 0 SPARK_BC / `bc_vm` is hello-only (MODEL ASK PRINT
HALT; LET encoded, not emitted by hello.sparkbc).

---

## No inventing

SoT order when adding ops or fixtures:

1. `docs/LANGUAGE.md` — statement forms
2. `examples/*.spark` and `selfhost/fixtures/` — programs
3. GAS / bootstrap dry-run stdout — exact model/ask/→/print lines
4. Goldens (`*.sparkbc`, lex jsonl) — encode what already exists
5. `docs/SPARK_BC.md` — ISA must cite 1–4

Do **not** invent opcodes or reply prose. C may bootstrap hello/mini
(`--compile`) until a Spark-hosted compiler exists — that is Phase 3,
not Stage 4 complete. `bootstrap/bc_pack_hello.c` packs the Phase 0
golden (encoding).

---

## Code-ladder

Each self-host phase **must** spawn or log a code-ladder pick
(alias + signals + why) before edits. Write
`reports/spark-selfhost-*.md` as the last file of the phase.
Never `voice` / `local-big`. Never treat `code-hard` as Sonnet.
Never auto-escalate to Opus / `judge`. Do not retarget Bifrost CEL.

---

## Coordination rules

- **A** does not own `bootstrap/`/`vm/` or `sparkasm/`.
- **B** does not rewrite `selfhost/` sources without A.
- **C** does not treat GAS syntax as IR SoT — `.sasm` is C’s SoT.
- Cross-links only; ops must already appear in `LANGUAGE.md`.

---

## Run (scaffold + seed)

```bash
# Phase 0 — bytecode on B (destination runner for hello)
./spark-bootstrap --run-bc selfhost/fixtures/hello.sparkbc
make test-sparkbc
make sparkbc-e2e   # TRAIN→STEP→ARTIFACT (dry; not SGD)

# Phase 2 — lex on B (same goldens as ./selfhost/spark-lex)
./spark-bootstrap --lex selfhost/fixtures/mini.spark
make test-selfhost-lex

# Phase 3 — C compile hello → .sparkbc → bc_vm (not compile.spark)
./spark-bootstrap --compile examples/hello.spark -o /tmp/hello.sparkbc
./spark-bootstrap --run-bc /tmp/hello.sparkbc
make test-sparkbc

# Stage 0 — still true
./spark --dry-run examples/hello.spark
./spark --dry-run selfhost/token_kinds.spark
./spark --dry-run selfhost/lexer.spark
./spark --dry-run selfhost/grammar.spark
./spark --dry-run selfhost/parser.spark
./spark --dry-run selfhost/fixtures/mini.spark
./spark --dry-run selfhost/fixtures/ops.spark
./spark --dry-run selfhost/fixtures/bootstrap_ops.spark
./spark --dry-run selfhost/fixtures/review_voice.spark
./spark --dry-run selfhost/fixtures/browser_dry.spark
./spark --dry-run selfhost/fixtures/ide_dry.spark
./spark --dry-run selfhost/fixtures/classify_dry.spark
./spark --dry-run selfhost/fixtures/let_dry.spark
./spark --dry-run selfhost/fixtures/ask_dry.spark
./spark --dry-run selfhost/fixtures/engine_dry.spark
./spark --dry-run selfhost/fixtures/ide_keys_dry.spark
./spark --dry-run selfhost/fixtures/binary_dry.spark
./spark --dry-run selfhost/fixtures/network_dry.spark
./spark --dry-run selfhost/fixtures/encrypt_dry.spark
./spark --dry-run selfhost/fixtures/cuda_dry.spark
./spark --dry-run selfhost/fixtures/os_dry.spark
./spark --dry-run selfhost/fixtures/pcie_dry.spark

# Real tokenize today (C aid; not the destination VM)
make selfhost-lex
./selfhost/spark-lex selfhost/fixtures/mini.spark
./selfhost/spark-lex selfhost/fixtures/ops.spark
./selfhost/spark-lex selfhost/fixtures/bootstrap_ops.spark
./selfhost/spark-lex selfhost/fixtures/review_voice.spark
./selfhost/spark-lex selfhost/fixtures/browser_dry.spark
./selfhost/spark-lex selfhost/fixtures/ide_dry.spark
./selfhost/spark-lex selfhost/fixtures/classify_dry.spark
./selfhost/spark-lex selfhost/fixtures/let_dry.spark
./selfhost/spark-lex selfhost/fixtures/ask_dry.spark
./selfhost/spark-lex selfhost/fixtures/engine_dry.spark
./selfhost/spark-lex selfhost/fixtures/ide_keys_dry.spark
./selfhost/spark-lex selfhost/fixtures/binary_dry.spark
./selfhost/spark-lex selfhost/fixtures/network_dry.spark
./selfhost/spark-lex selfhost/fixtures/encrypt_dry.spark
./selfhost/spark-lex selfhost/fixtures/cuda_dry.spark
./selfhost/spark-lex selfhost/fixtures/os_dry.spark
./selfhost/spark-lex selfhost/fixtures/pcie_dry.spark
make test-selfhost-lex
```
Peer reports when present:

- B: `reports/spark-vm-bootstrap-B-20260831.md`
- C: `reports/spark-native-assembler-C-20260831.md`
- A: `reports/spark-selfhost-A-20260831.md`
