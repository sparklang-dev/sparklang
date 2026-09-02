# SparkLang roadmap

Prioritized against the adoption bar. Status: **done** / **next** / **won't**
(near-term product focus). Details: [ADOPTION_BAR.md](ADOPTION_BAR.md).

## Done (this era)

- Public MIT repo, SparkLang branding, About disambiguation
- Changelog + release process doc
- `embed` / `retrieve` first-class ops + dry fixtures + `spark-rag-http`
- Dry-run escape hatch: `shell` / `run` allowlist fixtures
- `./spark --embed` FFI handshake stub
- Per-`ask` `[accounting]` line (dry zeros; live usage when present)
- Positioning: not a Bifrost plugin; dry-run first
- `http get` / `http post` + timeout + dry fixture files + live
  `./spark-http` (auth/retries still **next**)

## Next

| Track | What |
|-------|------|
| HTTP | Auth / bearer headers; retries |
| Extract | Schema validation + JSON-mode + retry on miss |
| Ask | Streaming token/SSE path |
| Eval | Expectation pass/fail harness (not only alias compare) |
| Escape | Live `--allow-shell` argv policy; `import spark` host embed |
| Accounting | Wall-clock latency on live ask; run-level rollup |
| LSP | Prefer editor LSP + highlighting over IDE chrome |
| Receptionist | Promote `examples/receptionist_goal.spark` off `[goal]` when transfer + eval syntax exist |
| Releases | Cut GitHub Release tags from CHANGELOG (see RELEASE.md) |

## Done (rename)

| Track | What |
|-------|------|
| Rename | Public `sparklang-dev/sparklang` live; private `sparklang-dev/sparklang` retained. Site sparklang.dev. CLI remains `spark`. |

## Won't (near-term focus)

| Drop | Why |
|------|-----|
| MITM / pcap / browser automation as hero | Distracts from AI workflow language |
| Homegrown Electron/PyQt IDE as hero chrome | Prefer LSP for editor story; **IDE tree kept** (hard-delete OWNER-CONFIRM **revoked** 2026-09-02) |
| Model-build as training product | Blueprint / eval sugar only |
| Production voice/telephony claim | Gaps remain (barge-in, EOU, SM, adapters) — gated demo only |
| Bifrost-as-identity | Gateway optional; any OpenAI-compatible URL |

## Voice gaps (honest)

If not shipping soon, keep voice off the production claim list:

- Barge-in, EOU / silence detection, latency budget
- Call state machine: transfer / hold / hangup / VM / DTMF / STT retry
- Named STT / TTS / telephony adapters as stable contracts
- Concurrency model for multi-call

Dry `listen` / `speak` / gated PSTN remain demos. See [VOICE.md](VOICE.md).
