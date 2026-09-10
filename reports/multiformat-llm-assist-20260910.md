# Multi-format PE + grounded LLM-assist decompile — 2026-09-10

Owner directive (Michael, 2026-09-10 03:29 CT): parity-matrix rows
"Multi-format ELF/PE — loss" and "LLM-assist decompile — na" →
"we need these". Both built for real, measured, no mocks, no
declared badges. Scoreboard/badge recompute is a parallel worker's
lane; this lane ships the capabilities + probe JSON evidence.

## 1. Multi-format PE support (real, measured)

`tools/binary/spark_binary_probe.c` now parses PE32/PE32+ for real,
same bounds-checked mmap discipline as the ELF side:

- MZ header check, `e_lfanew`, `PE\0\0` signature, COFF header
  (machine, timestamp, characteristics, section count ≤96),
  optional header (magic 0x10B/0x20B, entry RVA, image base,
  subsystem, NumberOfRvaAndSizes), section table walk (40-byte
  entries, long `/N` names resolved via the COFF string table),
  and the import directory (data dir 1): descriptor walk, DLL
  names, thunk walk (ILT, 32/64-bit, ordinal flag), function names
  from IMAGE_IMPORT_BY_NAME.
- `--pe PATH` strict flag; `--understand PATH` auto-detects MZ by
  magic and runs the PE walk. `--elf` stays ELF-strict.
- Fail loud on truncation / bad magic / unsupported optional magic:
  single `{"ok":false,"error":...}` JSON + exit 1. Import table is
  validated in a pre-pass before any printing, so a truncated file
  can never emit a partial/fabricated JSON prefix.
- JSON gains `"format":"pe32"|"pe32plus"` (ELF side unchanged).

### Fixtures (real PEs found on the box; no mingw present)

| Fixture | Format | Source | sha256 |
| --- | --- | --- | --- |
| `examples/fixtures/binary/winver-pe32plus.exe` | PE32+ (x86-64, GUI, 17 sections) | wine prefix `system32/winver.exe` | `7f1c587ac7140864a6c1c20f3cb1ea8b20cd6da6a07ed7cd37f27f51386c49cd` |
| `examples/fixtures/binary/csc-pe32.exe` | PE32 (i386, console, 3 sections) | wine prefix Mono `csc.exe` | `1f1c14c8f7bff93bbe433290963885a3ae3b13da6fdd24decb74c03d692fb6cb` |

`x86_64-w64-mingw32-gcc` is not installed on the box; per the
directive's fallback, real PEs were taken from the local wine
prefix and sha256-pinned in the tests/probe.

### objdump parity evidence (`make test-pe-probe`)

`tools/binary/test_pe_probe.py` diffs probe JSON against
`objdump -x` ground truth on both fixtures:

- entry: probe `entry_va` == objdump `start address`
  (winver `0x140001200`, csc `0x402cfe`) ✓
- sections: count + per-section `vsize` and `image_base+vaddr` ==
  objdump `Size`/`VMA` (17/17 and 3/3) ✓
- imports: DLL set and function-name set exactly match objdump's
  Import Tables (winver: comctl32/kernel32/shell32/ucrtbase, 14
  functions; csc: mscoree.dll `_CorExeMain`) ✓
- negatives: 6 truncated/corrupt copies (tiny, headers-only,
  mid-import-table, bad PE sig, bad MZ, bad optional magic) all
  fail loud, rc≠0, single `ok:false` JSON ✓

## 2. LLM-assist decompile (real, measured)

New `tools/decompile_assist.py` (CLI: `python3 tools/decompile_assist.py
FILE.sparkbc [--llm] [--json]`; make target `test-decompile-assist`):

- **Offline structural explainer (default):** deterministic
  narrative computed from the real dump via
  `sparklang.model_lab.bc_dump.analyze_bc` — sections, opcode
  histogram with code offsets, string-pool summary with xref users,
  xref narrative, entry/exit flow. No network, no LLM; output
  tracks input bytes.
- **`--llm` accelerator:** POSTs the dump JSON to the on-box Bifrost
  gateway (`AI_GATEWAY_URL`, default `http://127.0.0.1:4000`,
  path `/v1/chat/completions`) with alias `code` (env override
  `SPARK_DECOMPILE_ALIAS`; never a vendor model string). Optional
  `SPARK_GATEWAY_KEY` env → `Authorization: Bearer` (repo
  convention; no keys in code). 400/401/402/429/unreachable are
  normal states → degrade to offline, recorded honestly.
- **Grounding validator (always on):** every known SPARK_BC
  mnemonic mentioned must occur in the dump; backticked or
  "opcode X" claims must be real dump mnemonics; `strN`/`constN`
  references must be in range — all recomputed from the real bytes.
  Violation → `GroundingError`, rc 3, violations on stderr.

### Assist evidence (`make test-decompile-assist`, 7 gates)

- sensitivity: `spark-train-step.sparkbc` vs `spark-self.sparkbc`
  → different output, different sha256 ✓
- grounding negative: injected absent-but-known mnemonic
  (`TRAIN`-class pick computed per fixture), injected unknown
  opcode `` `ZWARP` ``, and out-of-range `str999`/`const999` all
  rejected ✓
- offline mode proven network-free (urlopen patched to raise) ✓
- --llm path with stubbed HTTP double: grounded aid accepted,
  fabricated aid rejected with rc 3, 402/429/URLError degrade ✓

Live gateway state at probe time: Bifrost up on `:4000`, alias
`code` resolves to a provider with no keys today (HTTP 400) →
measured `degraded_offline`. The accelerator path is real and
unit-proven with a stubbed gateway; the offline explainer is the
default and needs nothing.

## 3. Probe JSON schema (for the badge pass)

Emitted (committed) under `website/data/probes/`:

- `pe_multiformat.json` ← `tools/probe_pe.py` (`make probe-pe`)
- `llm_assist_decompile.json` ← `tools/probe_assist.py`
  (`make probe-assist`)

Schema (fixed filenames; re-runs overwrite with fresh `ts`):

```json
{
  "capability": "multi_format_elf_pe" | "llm_assist_decompile",
  "probe": "tools/probe_pe.py" | "tools/probe_assist.py",
  "input_sha256": "<sha256 of primary input fixture>",
  "measured": true,
  "ok": true,
  "details": { "…capability-specific measurements…" },
  "ts": "<RFC3339 UTC>"
}
```

`details` for PE: per-fixture `{path, sha256, sha256_pinned,
format, entry_va, entry_matches_objdump, section_count,
sections_match_objdump, import_dlls, imports_match_objdump,
import_function_count, ok}` + `negative_cases` map + ground-truth
tool id. For assist: per-input `{path, sha256, n_ops, grounding}`,
`sensitivity_distinct_outputs`, `injection_rejected`, and honest
`llm` block `{gateway, alias, state, grounding}` where state is
`ok` | `degraded_offline` | `grounding_rejected`.

Not touched (parallel worker owns): `tools/spark-bc-dump/decompile_bench.py`,
`website/data/decompile-scoreboard.json`, all `website/*.html`.

## 4. beats_claude note

`tools/binary/spark_binary_probe.c` JSON output has no
`beats_claude` field (verified by grep) — nothing to remove there.
No `beats_claude` markers in any file this lane added or edited.
The stale "never invent PE imports" note in the not-ELF branch was
updated to "never invent imports" since PE imports are now real.

## Gates

| Gate | Result |
| --- | --- |
| `make test-sparkbc` | PASS (`OK sparkbc`, dump tests ok) |
| `make test-decompile-compete` | PASS (`ok test_decompile_compete`) |
| `make test-spark-analyze` | PASS (4 tests OK) |
| `make test-pe-probe` (new) | PASS (`ok test_pe_probe`) |
| `make test-decompile-assist` (new) | PASS (`ok test_decompile_assist`) |
| `make probe-pe` / `make probe-assist` | both `ok:true`, JSON committed |
| C build (`make spark-binary-probe`) | clean, `-O2 -Wall -Wextra`, 0 warnings |

## PR / merge state

Branch `feat/multiformat-llm-assist` (worktree
`sparklang-wt-multiformat`; main checkout untouched). PR + merge
state: see chat return / this section's footer after land.
