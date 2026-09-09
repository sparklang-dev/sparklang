# SparkLang — the Spark programming language

**Spark** (public product name **SparkLang**, site [sparklang.dev](https://sparklang.dev/))
is a **language and runtime** for plain `.spark` files: dry-run fixtures,
compile/BC, playbooks, and the Spark IDE are the **core** story. Network/web
and voice/PSTN are **optional** language ops. Live `ask` against an
OpenAI-compatible gateway (`AI_GATEWAY_URL`, `./spark --live`) is **optional** —
not the product identity. Spark is **not** a Bifrost plugin, **not** Apache
Spark, and **not** AdaCore SPARK.

Default loop: dry-run / offline / no keys. Live gateway only when you opt in.

First-class surface: `ask`, `classify`, `extract`, `pipeline`, tools,
**model train/build/status** (real jobs — dry fixtures first),
**model reverse/inspect/compile/modify** (lab; keep special training),
**head abstain/train/attach/ask** (IDK gate on local LLMs),
**model analyze/compare/improve/plan** (eval helpers),
**review/builder/implement**, **os design/generate**,
browser/mitm, cuda/pcie, encrypt-to-model companion — one reviewable file.

**Trust:** [MIT LICENSE](LICENSE) ·
[GitHub](https://github.com/sparklang-dev/sparklang) · version **0.6.2**
([CHANGELOG](CHANGELOG.md); installer kit still **0.6.0** in
`website/downloads/manifest.json`) ·
[About](https://sparklang.dev/about.html)

**Names:** product = **SparkLang**; repo = `sparklang`; CLI = `spark`
(keep `./spark-bootstrap`). Not Apache Spark / AdaCore SPARK.

## Program with Spark

**Start here:** [docs/PROGRAMMING_GUIDE.md](docs/PROGRAMMING_GUIDE.md) —
build, dry vs live, syntax with real `examples/`, layout, debug, tests.

| Doc | Role |
|-----|------|
| **[AI models](docs/AI_MODELS.md)** | Model create/modify; dry-run first; optional live gateway |
| **[Model lab](docs/MODEL_LAB.md)** | Reverse → compile → build → modify; keep existing LoRA |
| **[Abstain / IDK heads](docs/ABSTAIN_HEADS.md)** | SELECT-before-SAMPLE; flagship `examples/no_invent.spark` |
| **[Program with Spark](docs/PROGRAMMING_GUIDE.md)** | Canonical how-to |
| **[AI playbooks](docs/AI_PLAYBOOKS.md)** | Coding playbooks + explicit model line |
| **[IDE](docs/IDE.md)** | Verified `ide` ops + interim Cursor editor |
| [LANGUAGE.md](docs/LANGUAGE.md) | Full statement reference |
| [ASK_LIVE.md](docs/ASK_LIVE.md) | Optional live gateway `ask` |
| [MODEL_ANALYSIS.md](docs/MODEL_ANALYSIS.md) | Model analyze/improve methodology |
| [VOICE.md](docs/VOICE.md) | STT/TTS (optional surface) |
| [ENCRYPT_GATEWAY.md](docs/ENCRYPT_GATEWAY.md) | Encrypt-to-model |
| [OS_DESIGN.md](docs/OS_DESIGN.md) | OS blueprints |
| [SELF_HOST.md](docs/SELF_HOST.md) | Contributor: A+B+C self-host path |

```bash
make
./spark --dry-run examples/hello.spark
./spark --dry-run examples/http_get.spark   # http get + fixture (no network)
./spark --dry-run examples/ide.spark    # review → builder → implement (not the IDE)
PYTHONPATH=python python -c "from sparklang import run; print(run('examples/hello.spark').ok)"
node -e "console.log(require('./js/sparklang').run('examples/hello.spark').ok)"
make test
```

## Spark IDE

**Honesty:** not Electron / not PyQt / not a full IDE chrome.

**IDE language ops (verified):** `ide new|open|save|run|buffer|ask|show`
+ `ide keys` / `ide key`. Usable e2e: open→ask→show, open→run→show,
open→save→reopen (`examples/ide_*.spark`). Paint = PPM with **status
path strip** + AI strip (`make test-ide-paint` — not a language op).
`ide show` → `./spark-engine-show`. Do not invent ops beyond
`docs/IDE.md`. **Authoring SoT DECIDED (A+B+C):** self-host (A); thin C
bootstrap (B); Spark-native assembler (C). GAS = disposable scaffold.
See `../reports/spark-vm-not-asm-pivot-20260831.md`.

```bash
./spark --dry-run examples/ide_hello.spark
./spark --dry-run examples/ide_ask_show.spark
./spark --dry-run examples/ide_save_reopen.spark
./spark --dry-run examples/ide_new_chain.spark
./spark --dry-run examples/ide_keys.spark
./spark --live examples/ask_live.spark   # optional; needs gateway
```

Status: **[docs/IDE.md](docs/IDE.md)**. No `./spark ide` ELF subcommand.
Flags: `--dry-run`, `--live`, `--allow-net`, `--allow-net-capture`,
`--pstn-live`, `--version`.

Optional interim: `make ide` → Cursor host (not product). Cursor Override
model routing is separate from SparkLang — see [AGENTS.md](AGENTS.md).
Spark `.spark` files use explicit model ids only (no alias pick).

**Marketing site (live):** https://sparklang.dev/ → 200 (CF Pages;
`website/` HTML only — Start here at `/docs/*.html`. Developer SoT stays
`docs/*.md` in this repo; raw markdown is not published.)

## Core vs optional

| Surface | Included |
|---------|----------|
| **Core** | Language + dry-run fixtures + playbooks + IDE language ops |
| **Optional** | Live gateway `ask` (`--live`); voice/PSTN (gated); browser/MITM; network capture |

## DX framing

**Cognitive / DX**: fewer lines, fewer glue bugs, faster iteration —
plus memo-friendly dry-run.

## Lowest practical level (owner hierarchy)

**Authoring SoT (2026-08-31):** **A + B bootstrap + C** — self-host
destination; thin C bootstrap; Spark-native assembler. Current GAS tree
is the **disposable running scaffold**, not forever SoT
(`../reports/spark-vm-not-asm-pivot-20260831.md`).

| Tier | What | In this repo (today) |
|------|------|----------------|
| 1. Machine language | CPU executes binary | `./spark` ELF64 |
| 2. Assembly | mnemonics → assembler | `asm/*.s` (GAS x86_64) — **scaffold**; replace with Spark-native assembler (C) |
| 3. HDL | parallel hardware | `hdl/classify_score.v` (synthesizable stub; **not** a taped-out chip) |

**Rejected as forever product authoring:** hand-written GAS, Python/Rust
VM shells. **Bootstrap (B):** thin native C VM until self-host (A) works —
not a Python/Rust interpreter product. Live OpenAI-compatible HTTP is a
**companion** (`./spark-ask-http` from `tools/ask/`) fork/exec’d only under
`--live` — **not linked** into the default dry-run ELF. Dry-run needs
**zero** network.

```bash
# Build machine code
make

# Proof it is asm→ELF, not a script
make machine-proof
file ./spark
# ELF 64-bit LSB executable, x86-64, statically linked

# Run (no network)
./spark --dry-run examples/hello.spark
./spark --dry-run examples/classify_intent.spark
./spark --dry-run examples/voice_turn.spark
./spark --dry-run examples/review_builder.spark

# Model analyze / compare / improve / build (fixture metrics)
./spark --dry-run examples/model_improve.spark

make test
make test-e2e-browser   # browser dry E2E (no display)
```

## Language surface

- **`ask` / `generate`** — model calls with slots; optional live via
  `./spark-ask-http` + `AI_GATEWAY_URL` ([docs/ASK_LIVE.md](docs/ASK_LIVE.md))
- **`classify`** — single/multi label enums + confidence
- **`extract`** — inline schemas
- **`pipeline` / `|`** — chain steps
- **`tool` / `with tools`** — declare tools once
- **`listen` / `speak` / `voice`** — STT/TTS session +
  `voice review|code|copy|model|pstn` ([docs/VOICE.md](docs/VOICE.md))
- **`review` / `builder` / `implement`** — static review (path/url/text),
  level pick (lower/mid/higher), codegen into `out/`
- **`model`** — set an explicit model id (HF / path / configured name)
  **or** `train` / `build` / `status` (real jobs; dry fixtures) plus
  `analyze` / `compare` / `improve` / `plan` (eval helpers)
  sugar; see [docs/MODEL_ANALYSIS.md](docs/MODEL_ANALYSIS.md))
- **`cuda` / `memory` / `pcie`** — asm `/dev/nvidia*` + `NV_ESC_*`
  ioctl; `mlock` pin; **live PCIe link** via sysfs
  (`asm/pcie_ops.s` — gen/width current+max, `downgraded`)
- **`binary`** — open / elf / disasm / understand / kernelmod / firmware.
  Disasm/understand dump **every** ELF section under
  `out/decompile/<basename>/` (`ALL_SECTIONS.*` + `.raw` + `lifted/`);
  huge files stream fully (checkpoint/resume)
- **`network`** — capture probe / capture (fixture unless
  `--allow-net-capture` + `CAP_NET_RAW`; CAP miss exit 4) /
  open pcap / analyze / explain
- **`os`** — design / specify / generate / build / explain AI-agent OS
  blueprints (`out/os/<name>/`; [docs/OS_DESIGN.md](docs/OS_DESIGN.md))
- **`browser` / `mitm`** — language SoT in `asm/browser_ops.s`:
  `run` / `goto` / `gui` / `flags` + `ca-init|status|install` +
  `enable` / `har export` / `disable_quic` / `quic status|smoke`
  (real HAR under `out/browser/`). Host GUI only via
  `browser gui` + `--live`
- **`crypto` / `encrypt` / `gateway`** — encrypt-to-model companion
  (AES-256-GCM). Agent seals envelopes; `spark-enc-gateway` decrypts
  at the model boundary then calls the configured chat backend. See
  [docs/ENCRYPT_GATEWAY.md](docs/ENCRYPT_GATEWAY.md).

**MITM CA** mint/install stays `mitm ca-*` → `./spark-mitm-ca` (separate
from the encrypt-to-model gateway).

**Safety:** review never evaluates web JS. `review url` uses
`./spark-review-url` (**B** default: `file://` / local path only;
**A** opt-in: `http(s)` with `--allow-net` → real curl fetch + scan).
Remote without `--allow-net` exits non-zero with a clear
`--allow-net` error — no network dial, no QUESTION menu.
Network **capture** stays gated behind `--allow-net-capture`. Dry-run
network **never** claims a live sniff without `--allow-net-capture`.
Probe with `network capture probe` / `./spark-net-capture --probe`
(`claimed:false`). Live CAP miss → exit **4**.
Model **train** / **build** submit jobs (dry fixtures or live
`spark-train-http`); see [docs/MODEL_TRAINING.md](docs/MODEL_TRAINING.md).
**`os generate`** writes educational stubs only — never reboots or
installs an OS on the developer host.
See [docs/LANGUAGE.md](docs/LANGUAGE.md).

## Browser entrypoints (SoT)

| Mode | Command |
|------|---------|
| Dry (no display) | `./spark --dry-run examples/browser_main.spark` |
| Live product | `cd ../spark-browser && make run` → `./spark --live browser/run.spark` |
| Dry E2E | `make test-e2e-browser` |

`python3 -m spark_browser run` is **not** a product entry (Qt debug
only via `make run-host` in spark-browser).

## CUDA

`cuda probe|memstat|prefer` are **asm syscalls** in `asm/cuda_ops.s`:
`open` `/dev/nvidiactl` + `/dev/nvidia0` + `/dev/nvidia-uvm`, then
`ioctl` `NV_ESC_CARD_INFO` / `CHECK_VERSION`. Prefer Device Minor **0** for interactive compute. Never prefer
reserved voice-only GPU minors. `memory pin` =
`mmap`+`mlock`.

`cuda pcie` / `pcie probe` live in **`asm/pcie_ops.s`**: read
`/sys/bus/pci/devices/<bdf>/current_link_*` + `max_link_*`, flag
`downgraded` when width or speed &lt; max. Measured numbers only.
Optional NVML cross-check: `make spark-cuda`.

```bash
./spark --dry-run examples/cuda_mem.spark
./spark --dry-run examples/cuda_pcie.spark
```

## Env (optional live ask)

See [docs/ASK_LIVE.md](docs/ASK_LIVE.md). Dry-run needs none of this.

```bash
make                            # includes spark-ask-http
export AI_GATEWAY_URL=http://127.0.0.1:4000
export OPENAI_API_KEY=…         # gateway Bearer; never commit
./spark --live examples/ask_live.spark
```

- `AI_GATEWAY_URL` / `OPENAI_API_KEY` (or `SPARK_GATEWAY_KEY`)
- Pass an **explicit** model id (HF / path / configured name)
- Public gateway tunnel probes: dedicated probe credential via
  `tools/ask/probe_public.sh` — 401 → credential unavailable
- `SPARK_STT_URL` / `SPARK_TTS_URL` — optional speech endpoints
  (require `SPARK_STT_NET=1` / `SPARK_TTS_NET=1` or `SPARK_SPEECH_NET=1`)
- Live speech: `./spark-stt-tts` via `--live` (`docs/VOICE.md`)
- Dry-run / `make test` stay **offline** (never call spark-ask-http
  or vendor STT/TTS)

## Layout

```
asm/spark.s              # VM entry + flags + fork_exec_wait (GAS scaffold)
asm/engine_*.s           # Engine B fetch/parse/css/layout/paint/js/show
asm/ide_*.s              # IDE buffer / keys / paint wire
tools/ask/               # spark-ask-http (OpenAI-compatible)
tools/engine/            # spark-engine-fetch-tls (OpenSSL BIO)
tools/browser/           # spark-engine-show + parked host helpers
bootstrap/               # lane B thin C VM (spark-bootstrap)
sparkasm/                # lane C Spark-native assembler (.sasm)
selfhost/                # lane A seeds + lex.c goldens
hdl/classify_score.v     # parallel classify HDL stub
examples/*.spark
docs/AI_MODELS.md                # user-facing model create/modify + roadmap
docs/ABSTAIN_HEADS.md      # IDK / abstain heads + spark-abstain
docs/PROGRAMMING_GUIDE.md  # canonical programming guide
docs/IDE.md                # Spark IDE + CLI loop
docs/LANGUAGE.md
docs/ASK_LIVE.md
docs/VOICE.md
docs/OS_DESIGN.md
docs/SELF_HOST.md          # A+B+C self-host path
website/                   # sparklang.dev marketing (HTML docs only)
LICENSE
CHANGELOG.md
Makefile
```

## What this is not

- Not a Bifrost plugin / not “Spark requires Bifrost”
- Not Apache Spark / Databricks; not AdaCore SPARK
- Not a custom CPU ISA or a production bare-metal OS (os = **blueprint stubs**)
- Not full ES / full CSS / Google.com / Electron / a finished self-host compiler
- Not a vendor voice product — Spark stays generic STT/TTS
- Not a claim of FPGA bitstream shipping in CI
- Not silent GPU train — dry-run never starts jobs; live needs
  `SPARK_TRAIN_*` + allowlist / URL (see MODEL_TRAINING.md)
- Not a wipe/replace of the host Linux — never reboot / never `dd` live disks
- Encrypt-to-model ≠ redact/tokenize; CA mint is still `mitm ca-*` only
