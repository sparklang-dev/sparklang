# `selfhost/` — Spark-on-Spark seed (lane A)

**Goal:** compiler + VM authored in Spark, run by bootstrap **B**,
emitting machine code via assembler **C**. Architecture:
[`docs/SELF_HOST.md`](../docs/SELF_HOST.md).

**Not a full compiler.** Seeds + `lex.c` tokenize aid only. Stage 4–5
are future evidence gates.

## Today vs goal

| Surface | Today (Stage 0) | Goal |
|---------|-----------------|------|
| Run `selfhost/*.spark` | Current GAS `./spark --dry-run` | Bootstrap **B** C VM |
| Tokenize `.spark` text | `selfhost/spark-lex` (C aid) + seed `.spark` docs | Lexer in Spark on B |
| Assemble objects | GAS `as` for scaffold; **C** `sparkasm/` growing | C IR → objects; later Spark-hosted |
| Full compiler/VM in Spark | **Not started** (seeds only) | Stage 4–5 in SELF_HOST.md |

## Next gate

**Stage 3:** Spark lexer/parser seeds run on bootstrap **B** and match
lex goldens. Stage 1 (B subset) and Stage 2 (C phase-1) are **already
real** — see `docs/SELF_HOST.md` + `bootstrap/README.md` +
`sparkasm/README.md`. Until Stage 3: grow dry-runnable seeds + `lex.c`
coverage only. **Not** a full compiler.

## What dry-runs on today’s `./spark`

Valid language programs (ops from `LANGUAGE.md`):

```bash
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
```

They use `model` / `ask` / `generate` / `print` / `review path|text` / `|` / `classify`
/ `tool` / `with` / `extract` / `listen` / `speak` / `voice` / `pipeline`
/ `browser` / `mitm` / `ide` / `let` / `engine` / `binary` / `network` /
`crypto` / `encrypt` / `gateway` / `cuda` / `memory` / `os` / `pcie` (Stage 1
catalog keywords). They do **not** invent a `lex`
language op. Real scanning today is `./selfhost/spark-lex` (see below). GAS
scaffold **pads** `let` dumps (exit 0; make redirects); B dry-run is clean.

## Real tokenize (bootstrap aid)

```bash
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

Emits one JSON object per token on stdout. Kind names match
`token_kinds.spark`. This C lexer is a **ladder**: replace it when
`lexer.spark` (grown) runs on B and matches the same goldens.

## Files

| File | Notes |
|------|-------|
| `token_kinds.spark` | Kind catalog; dry-runs |
| `lexer.spark` | Lexer algorithm seed; dry-runs |
| `grammar.spark` | Statement grammar catalog; dry-runs |
| `parser.spark` | AST/parse plan seed; dry-runs |
| `compile.spark` | Compiler seed catalog (MODEL/ASK/PRINT/HALT) |
| `compile_train.spark` | Train slice; `--compile` emits TRAIN `0x26` / TRAIN_STATUS `0x27` |
| `fixtures/mini.spark` | Hello-scale lex input |
| `fixtures/ops.spark` | PIPE + review path + NUMBER + classify |
| `fixtures/bootstrap_ops.spark` | Stage 1 B subset: tool/with/extract/listen/speak/pipeline |
| `fixtures/review_voice.spark` | review path/text + voice{listen/speak} |
| `fixtures/browser_dry.spark` | browser run/goto + mitm enable |
| `fixtures/ide_dry.spark` | ide open/run/ask/show |
| `fixtures/classify_dry.spark` | model + classify (+ multi) + print |
| `fixtures/let_dry.spark` | model + let + print (`let` KEYWORD) |
| `fixtures/ask_dry.spark` | model + ask + generate + print |
| `fixtures/engine_dry.spark` | engine fetch/parse/css/layout (B Stage 1) |
| `fixtures/ide_keys_dry.spark` | ide keys / ide key open|show|save|run|quit |
| `fixtures/binary_dry.spark` | binary open/elf/disasm/understand/kernelmod/firmware |
| `fixtures/network_dry.spark` | network capture/open/analyze/explain |
| `fixtures/encrypt_dry.spark` | crypto/encrypt/gateway seal path |
| `fixtures/cuda_dry.spark` | cuda probe/memstat/prefer + memory pin |
| `fixtures/os_dry.spark` | os design/specify/generate/build/explain |
| `fixtures/pcie_dry.spark` | cuda pcie / pcie probe / pcie explain |
| `lex.c` | Byte lexer (A-owned; not B VM, not C assembler) |
| `expected_mini.tokens.jsonl` | Golden for mini |
| `expected_ops.tokens.jsonl` | Golden for ops |
| `expected_bootstrap_ops.tokens.jsonl` | Golden for bootstrap_ops |
| `expected_review_voice.tokens.jsonl` | Golden for review_voice |
| `expected_browser_dry.tokens.jsonl` | Golden for browser_dry |
| `expected_ide_dry.tokens.jsonl` | Golden for ide_dry |
| `expected_classify_dry.tokens.jsonl` | Golden for classify_dry |
| `expected_let_dry.tokens.jsonl` | Golden for let_dry |
| `expected_ask_dry.tokens.jsonl` | Golden for ask_dry |
| `expected_engine_dry.tokens.jsonl` | Golden for engine_dry |
| `expected_ide_keys_dry.tokens.jsonl` | Golden for ide_keys_dry |
| `expected_binary_dry.tokens.jsonl` | Golden for binary_dry |
| `expected_network_dry.tokens.jsonl` | Golden for network_dry |
| `expected_encrypt_dry.tokens.jsonl` | Golden for encrypt_dry |
| `expected_cuda_dry.tokens.jsonl` | Golden for cuda_dry |
| `expected_os_dry.tokens.jsonl` | Golden for os_dry |
| `expected_pcie_dry.tokens.jsonl` | Golden for pcie_dry |

## Bootstrap-only / future

When B cannot run a richer Spark lexer yet, keep new algorithms in
`.spark` comments + `lex.c` until B’s ops matrix covers what the
Spark lexer needs (`let`/`print` first; string ops later). Mark any
file that requires B-only ops with a top comment:

```
# bootstrap-only: requires B op X — not valid on GAS ./spark
```

No such file yet — everything here dry-runs on GAS **or** is the C
aid.

## Not owned here

- `bootstrap/` / `vm/` → lane **B**
- `sparkasm/` → lane **C**
- `asm/*.s` scaffold → disposable; do not deepen as product SoT
