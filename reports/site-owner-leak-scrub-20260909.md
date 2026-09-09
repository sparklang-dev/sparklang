# Site owner-leak scrub — 2026-09-09

## Verdict

Public sparklang.dev living docs no longer show `(owner hierarchy)`,
`owner cite`, or agent `*-lane` jargon on `/docs/language` (and matching
regen pages). Deployed production Pages from commit `e8bd42e`.

## Exact replacement

| Before | After |
|--------|--------|
| `## Implementation tiers (owner hierarchy)` | `## Implementation tiers` |
| HTML id `implementation-tiers-owner-hierarchy` | `implementation-tiers` |
| `## Lowest practical level (owner hierarchy)` | `## Lowest practical level` |

## Scope

- Branch: `chore/site-owner-leak-scrub`
- PR: https://github.com/sparklang-dev/sparklang/pull/52
- Commit: `e8bd42eae304bd5af32967a62ecfd7895868fd38`
- Files touched (scrub commit): **52**
- CHANGELOG: **0.6.59**
- Pages deploy id: `caa9b561-9156-451a-89cb-b7acbfa1c43a`
- Preview: https://caa9b561.sparklang-dev.pages.dev

## Also scrubbed (same pass)

- Operator parentheticals: `owner cite`, `owner addendum`, `owner host`,
  `owner only` (headings), `(owner 2026-…)`, `OWNER-CONFIRM` on recent
  changelog / roadmap / adoption-bar
- Lane letters in living docs → plain English (SDK pack, helpers, LLM
  research, eval harness, etc.)
- Meta descriptions: removed per-page “Never 6000” / “Does not beat Claude”
  spam; honest measurement note kept on eval (and coder/factory body notes)
- Public README: dropped SoapBox-local
  `../reports/spark-vm-not-asm-pivot-20260831.md`
- Light SVG footer + recent CHANGELOG title scrub; mirrored
  `website/CHANGELOG.html`

## Proof

```bash
curl -sL https://sparklang.dev/docs/language \
  | rg -i 'owner hierarchy|owner cite|\b[A-Z]-lane\b'
# → no matches (CLEAN)

curl -sL https://sparklang.dev/docs/language \
  | rg -n 'implementation-tiers|Implementation tiers'
# → <h2 id="implementation-tiers">Implementation tiers</h2>
```

`make docs-check` green before land.

## Never (unchanged)

No RTX PRO 6000 train, no “beat Claude” product claims invented, no host
reboot, no staff mail, no secrets printed.
