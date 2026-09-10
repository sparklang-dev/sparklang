# SparkLang competitive weaknesses — 2026-09-09

## Code-ladder pick

- alias: `code`
- signals: multi-file daily / site+tools+docs / no error storm
- why: close shipable competitive gaps (LSP, dry receptionist, ELF probe honesty)
- execution: did-work
- never: voice / local-big / code-hard-as-sonnet / opus / judge

## Inventory (sources)

| Source | Weakness found |
|--------|----------------|
| ROADMAP “Next” | Eval still listed (stale — already done); LSP missing; receptionist still `[goal]` only |
| ADOPTION_BAR | Prefer LSP over IDE chrome; dry receptionist gap; production transfer SM |
| Decompile scoreboard #44 | 8 win / 1 tie / 1 loss / 1 N/A — loss = Multi-format ELF/PE |
| OpenBin methods | Ideas only — local project loop already shipped; no clone |
| Extension | TextMate only; activation on one command; no diagnostics |
| Factory / sensory reports | Deeper attn / eyes stub / beat-Claude — **out of scope** (honesty) |

## Prioritized + shipped

| Weakness | Fix | Residual |
|----------|-----|----------|
| No real editor language support | `tools/spark_lsp` stdio LSP + extension v0.2 (hover/completion/`--check` diags); `docs/LSP.md`; nav Runtime → LSP | Not full semantic VM analysis; no publish to marketplace |
| Receptionist only `[goal]` | `examples/receptionist.spark` dry path + expect gates; goal file keeps live transfer SM marker | Live transfer/hold/hangup/barge-in language still **goal** |
| ELF/PE compete loss opaque | `spark-binary-probe --elf` emits sections JSON + `claim: local_elf_probe_not_ghidra`; scoreboard `elf_local_probe` | **Still loss** on Multi-format ELF/PE (honest) |
| Stale ROADMAP/ADOPTION | Eval + LSP marked done; dry receptionist done; transfer SM goal | GitHub Release tag lag; voice telephony won't-soon |

## Proof

```bash
make test-spark-lsp          # 6 OK
./spark --dry-run examples/receptionist.spark   # exit 0, 5 expect passes
./spark-binary-probe --elf ./spark              # op=elf, sections listed
make docs-check              # 45 pages OK
make decompile-bench         # round_trip 100%; elf_local_probe ok
```

## PR / SHA

| Item | Value |
|------|-------|
| Branch | `feat/competitive-weaknesses` |
| PR | *(fill after open)* |
| Tip | *(fill after merge)* |
| Changelog | **0.6.60** |

## Still weak (not closed this land)

- Live receptionist transfer / hold / hangup / barge-in
- Ghidra-class ELF/PE decompile (deliberate non-goal; SPARK_BC first)
- Full transformer decode / eyes runtime
- Beat Claude (never claimed)
- RTX PRO 6000 (never)
- OpenBin product clone (never — methods only)
- Cutting GitHub Release tags from CHANGELOG (ROADMAP next residual)
