# Decompile / inspect / disassemble

How to **read** SPARK_BC with Spark / SparkLang tools — step by
step, with screenshots and tool-layout diagrams. Dump tools read
**real** `.sparkbc` from `--compile`. This page is **inspect /
disasm**, not lossless source recovery.

Related research: [LLM decompile research](research/LLM_DECOMPILE.md)
(site: [/docs/llm-decompile.html](/docs/llm-decompile.html)) —
DecompAI (agent) vs seq2seq models, LLM4Decompile, EmergentMind
survey, Quarkslab article + RE category (LLM ≠ verified SoT),
Plain English demystify overview, OpenBin (online product — not
Spark SoT; third-party trust/IP), recompile ≠ semantic fidelity.
**Compete / scoreboard:** [DECOMPILE_COMPETE.md](DECOMPILE_COMPETE.md)
([/docs/decompile-compete.html](/docs/decompile-compete.html)) —
parity matrix + measured `make decompile-bench` JSON (no fake
“beats all”).
Mermaid factory overview: [DIAGRAMS.md](DIAGRAMS.md)
([/docs/diagrams.html](/docs/diagrams.html)).

**Never** claim an LLM perfectly decompiles SPARK_BC. **Never**
6000. Does **not** beat Claude. Do **not** publish “beats
Ghidra/IDA/…” without measured scoreboard JSON.

## Tool-function diagrams

### Compile path

![Compile path: source to SPARK_BC to run/train/serve](/docs/images/diagram-compile-path.svg?v=0.6.58)

*Caption: `.spark` → bootstrap / GAS assembler → `.sparkbc`
(SPARK_BC) → `--run-bc` / TRAIN·STEP / serve. Helpers, published
shadow-builds, and the SDK GUI wrap the same SoT — they do not
invent bytecode.*

### Decompile path

![Decompile path: BC to dump to readable view](/docs/images/diagram-decompile-path.svg?v=0.6.58)

*Caption: `.sparkbc` → `dump.py` (disasm/inspect) → readable hex +
mnemonics (or stub JSON / `--run-bc`). Optional edit is of the
`.spark` source, then **recompile** — dashed because dump is not a
lossless BC→source decompiler.*

### Helpers · shadow-build · SDK/IDE GUI

![Helpers shadow-build and GUI placement](/docs/images/diagram-helpers-gui.svg?v=0.6.58)

*Caption: Deterministic SPARK_BC SoT in the center. Helpers
(`Makefile`, `sparkc`, tests), shadow-build
(`docs/examples/*.sparkbc`), and SDK/IDE GUI (`spark-bc-gui`) sit
around it and call the same compile/dump paths.*

### Deterministic tools vs LLM assist

![Deterministic Spark vs optional LLM assist](/docs/images/diagram-deterministic-vs-llm.svg?v=0.6.58)

*Caption: Left = Spark SoT (compile, dump, run). Right = optional
LLM assist later (names/comments/drafts) — **never** the SoT for
`.sparkbc` bytes. See the research note for citations.*

## Step-by-step — CLI (primary today)

### 1. Build tools (once)

```bash
make spark-bootstrap spark
```

`sparkc` is a symlink to `spark-bootstrap`. GAS `./spark --compile`
thin-forks the same packer.

### 2. Dump a published `.sparkbc`

```bash
PYTHONPATH=python python3 tools/spark-bc-dump/dump.py \
  docs/examples/spark-train-step.sparkbc \
  --source examples/spark_train_step.spark \
  --command './spark-bootstrap --compile examples/spark_train_step.spark -o docs/examples/spark-train-step.sparkbc' \
  -o /tmp/spark-train-step-bc.txt
```

![CLI dump of SPARK_BC](/docs/images/decompile-cli-dump.png?v=0.6.58)

*Caption: Real terminal capture of `tools/spark-bc-dump/dump.py` on
`docs/examples/spark-train-step.sparkbc` — magic `SPBC`, pools,
opcode listing. Not invented hex.*

Loader / formatters: `python/sparklang/model_lab/bc_dump.py`
(sections, string **symbols**, const/op **xrefs**, `--json` /
`--html` export). Units: `tools/spark-bc-dump/test_dump.py` via
`make test-sparkbc`; richer dump gate
`make test-decompile-compete`.

**Round-trip (SoT win, loud):** `make decompile-roundtrip` —
compile → dump → recompile → sha256 match on published fixtures.

**Analysis project:** `tools/spark-bc-dump/analyze_project.py`
writes `dump.txt` / `dump.json` / `dump.html` / `report.md` under
an output folder (local-only).

**Bench / scoreboard:** `make decompile-bench` →
`website/data/decompile-scoreboard.json`.

Published dump text (no rebuild): `docs/examples/*-bc.txt` (site:
`website/docs/examples/`).

### 3. Stub JSON (builder metadata)

```bash
PYTHONPATH=python python3 tools/spark-bc-dump/dump.py \
  docs/examples/spark-builder.sparkbc --stub -o /tmp/stub.json
```

![CLI --stub JSON](/docs/images/decompile-cli-stub.png?v=0.6.58)

*Caption: Real `--stub` JSON from `spark-builder.sparkbc` — status,
sha256, magic, version. Still inspect metadata, not source recovery.*

### 4. Inspect behavior with `--run-bc`

```bash
./spark-bootstrap --run-bc docs/examples/spark-train-step.sparkbc
./spark --run-bc docs/examples/spark-train-step.sparkbc   # GAS → bc_vm
```

![CLI --run-bc dry VM](/docs/images/decompile-cli-runbc.png?v=0.6.58)

*Caption: Real `./spark-bootstrap --run-bc` dry bytecode VM lines.
TRAIN/STEP contracts: [SPARK_BC.md](SPARK_BC.md).*

### 5. CLI help (flags)

![CLI dump.py --help](/docs/images/decompile-cli-help.png?v=0.6.58)

*Caption: Captured `dump.py --help` — `--stub`, `--weights`,
`--serve` (tiny CPU forward; not production LLM).*

### 6. Init weights from bytecode (not trained)

```bash
PYTHONPATH=python python3 tools/spark-bc-dump/dump.py \
  docs/examples/spark-self.sparkbc \
  --weights /tmp/spark-self.init.safetensors
```

Emits Spark-created Xavier init (`trained: false`). See
[BUILD_MODELS.md](BUILD_MODELS.md).

## Graphical path (SDK pack — I-lane)

I-lane ships `tools/spark_bc_gui` / `bin/spark-bc-gui` (tkinter) that
calls real `--compile` + `bc_dump.format_dump`. Prefer the SDK pack
from [Downloads](/downloads.html) / `make sdk-pack`. CLI remains the
documented primary path on this page.

When the SDK pack is installed:

```bash
./bin/spark-bc-gui
# or: PYTHONPATH=tools:python python3 -m spark_bc_gui
```

Buttons: **Compile → .sparkbc**, **Decompile .sparkbc**, open
source / `.sparkbc`, save dump, load sample. See also
[sdk-ide-download](/docs/sdk-ide-download.html).

![Annotated SPARK_BC GUI](/docs/images/decompile-gui-sparkbc.png?v=0.6.58)

*Caption: Annotated layout matching `tools/spark_bc_gui` chrome.
Right pane text is **real** `dump.py` output (same capture as the
CLI screenshot). Interactive Tk GUI ships with the SDK download
pack — headed capture was blocked; this mock is labeled honestly.*

## Model lab reverse / inspect

```bash
./spark --dry-run examples/model_lab.spark
make test-model-lab
```

`model reverse` / `inspect` read local `config.json` + safetensors
**index names** only — no tensor body theft.
[MODEL_LAB.md](MODEL_LAB.md).

## ELF / machine disassembly (not SPARK_BC)

```bash
make machine-proof   # ELF64 + _start when binary exists
```

Language `binary` artifacts under `out/decompile/<basename>/`
(`ALL_SECTIONS.disasm`, …) are **ELF section dumps**, not SPARK_BC
decode. Do not confuse with `tools/spark-bc-dump`.

## sparkasm objects

```bash
make -C sparkasm test
```

Host `objdump` on assembled objects if needed — no Spark-branded
SPARK_BC↔ELF round-trip claim beyond `test-bc-emit`.

## What is not “decompile”

| Claim | Status |
|-------|--------|
| Hex + opcode mnemonics for `.sparkbc` | **implemented** (`dump.py`) |
| Symbols / xrefs / sections / JSON+HTML | **implemented** (`analyze_bc`) |
| Compile→dump→recompile hash | **implemented** (`decompile-roundtrip`) |
| Analysis project folder + report | **implemented** (`analyze_project.py`) |
| Measured compete scoreboard | **implemented** (`decompile-bench`) |
| Recover original `.spark` losslessly | **not** — inspect, not source decompiler |
| Beat Ghidra/IDA on ELF/PE | **not claimed** (loss / N/A on that domain) |
| LLM perfectly decompiles SPARK_BC | **never claimed** |
| Attention head activation maps | **not** — see [ATTENTION_FORWARD.md](ATTENTION_FORWARD.md) |
| Closed-weight model theft | **forbidden** — reverse stays index-only |

## Related

- [Compile](COMPILE.md) · [Build models](BUILD_MODELS.md)
- [SPARK_BUILDER.md](SPARK_BUILDER.md) · [SPARK_BC.md](SPARK_BC.md)
- [Factory hub](FACTORY.md) · [LLM decompile research](research/LLM_DECOMPILE.md)
- [Decompile compete / scoreboard](DECOMPILE_COMPETE.md)
- Screenshots + diagrams: `website/docs/images/decompile-*`,
  `website/docs/images/diagram-*`
