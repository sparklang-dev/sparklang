# Decompile compete — capability + measured scoreboard

Honest path to compete at every level on **SPARK_BC** without
false marketing. Spark / SparkLang only.

**Never** publish “Spark beats Ghidra / IDA / Binary Ninja /
LLM4Decompile / OpenBin” without the measured JSON from
`make decompile-bench`. **Never** 6000. **Does not** beat Claude.
Do **not** copy OpenBin code.

Related: [DECOMPILE.md](DECOMPILE.md) ·
[research/LLM_DECOMPILE.md](research/LLM_DECOMPILE.md) ·
site [/docs/decompile-compete.html](/docs/decompile-compete.html).

## Beat-axes (SPARK_BC domain — where we can actually win)

| Axis | Why it is a Spark win |
|------|------------------------|
| **100% round-trip** | `compile → dump → recompile` same `.spark` → identical sha256 on published fixtures (`tools/spark-bc-dump/roundtrip.py`) |
| **Best structured dump** | Sections + string symbols + const/op xrefs + txt/JSON/HTML export (`bc_dump.analyze_bc`) |
| **Best local privacy** | No upload — analysis project stays on disk |
| **Integrated train / weights** | Same BC drives TRAIN/STEP + init safetensors |

Classic RE tools win **ELF/PE/mach-O** interactive decompile.
That is **loss / N/A** for Spark SoT — not a silent claim.

## Feature parity matrix

Legend: **win** / **tie** / **loss** / **na** (wrong domain or not
claimed). Values are also emitted in
`website/data/decompile-scoreboard.json` by the bench.

| Category | Spark | OpenBin | Ghidra | IDA | Binja | LLM4Decompile |
|----------|-------|---------|--------|-----|-------|---------------|
| Native dump fidelity (SPARK_BC) | win | na | na | na | na | na |
| Round-trip reassemble (compile hash) | win | na | loss | loss | loss | loss |
| IDE explore | win | tie | tie | tie | tie | na |
| Ask / voice assist | tie | tie | na | na | na | tie |
| Report export (txt/json/html project) | win | tie | tie | tie | tie | na |
| Multi-format ELF/PE | loss | win | win | win | win | win |
| LLM-assist decompile | na | win | tie | tie | tie | win |
| Batch / fixtures harness | win | tie | tie | tie | tie | tie |
| Shadows / helpers | win | na | na | na | na | na |
| Local privacy (no upload) | win | loss | win | win | win | tie |
| Integrated train / weights | win | na | na | na | na | na |

## Commands

```bash
make spark-bootstrap spark
make test-decompile-compete   # unit: richer dump + project
make decompile-roundtrip      # compile→dump→recompile hash
make decompile-bench          # metrics + scoreboard JSON
```

Analysis project (single file):

```bash
PYTHONPATH=python python3 tools/spark-bc-dump/analyze_project.py \
  docs/examples/spark-train-step.sparkbc \
  -o out/analyze/train-step \
  --source examples/spark_train_step.spark
```

Richer dump exports:

```bash
PYTHONPATH=python python3 tools/spark-bc-dump/dump.py \
  docs/examples/spark-train-step.sparkbc --json -o /tmp/bc.json
PYTHONPATH=python python3 tools/spark-bc-dump/dump.py \
  docs/examples/spark-train-step.sparkbc --html -o /tmp/bc.html
```

## Measured scoreboard (data-driven)

After `make decompile-bench`:

- `website/data/decompile-scoreboard.json`
- `docs/examples/decompile-scoreboard.json` (mirror)
- sample project: `out/decompile-bench/sample-project/`

The site page loads the JSON and renders win/tie/loss/na from
**disk data** — no hand-painted green checkmarks.

External tools (objdump, r2, ghidra, ida, binaryninja, openbin)
are probed; if absent → `status: absent` / `verdict: skip`. If
present but not a SPARK_BC decoder → `verdict: na-sparkbc`.

## What is still not claimed

| Claim | Status |
|-------|--------|
| Lossless BC → `.spark` source | **not** implemented |
| Spark beats Ghidra on ELF | **false / loss** |
| LLM perfectly decompiles SPARK_BC | **never** |
| OpenBin clone | **never** — local SoT only |

## Related

- [DECOMPILE.md](DECOMPILE.md) · [SPARK_BC.md](SPARK_BC.md)
- [TOOLS_HELPERS.md](TOOLS_HELPERS.md) · [SPARKBC_MAKE.md](SPARKBC_MAKE.md)
- [FACTORY.md](FACTORY.md) · [CI_PAGES.md](CI_PAGES.md)

<div id="decompile-scoreboard-mount" class="doc__callout" role="region" aria-label="Measured scoreboard">
  <p><strong>Live measured scoreboard</strong> — loaded from
  <code>/data/decompile-scoreboard.json</code> after
  <code>make decompile-bench</code>. Empty box means regenerate JSON.</p>
  <div id="decompile-scoreboard-body"></div>
</div>
<script src="/js/decompile-scoreboard.js"></script>
