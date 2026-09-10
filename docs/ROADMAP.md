# SparkLang roadmap

Prioritized against the adoption bar. Status: **done** / **next** / **won't**
(near-term product focus). Details: [ADOPTION_BAR.md](ADOPTION_BAR.md).

## Done (this era)

- Public MIT repo, SparkLang branding, About disambiguation
- Changelog + release process doc
- `embed` / `retrieve` first-class ops + dry fixtures + `spark-rag-http`
- Dry-run escape hatch: `shell` / `run` allowlist fixtures
- Live `--allow-shell`: `./spark-shell` argv `execve` (echo|true|false)
- Host embed: Python + JS (`js/sparklang`) + C (`host/c/sparklang.h`);
 `./spark --embed` JSON handshake
- Per-`ask` `[accounting]` line (dry zeros; live wall-clock + usage)
- Live run-level `[accounting-run]` rollup (`spark-ask-http --rollup`)
- Streaming `ask`: `./spark-ask-http --stream` SSE + `ask stream`
 language form (live); dry prints `stream=1`
- Live `extract`: schema validate + retry-on-miss (`--retries`,
 `--stub-file` offline); forks `./spark-ask-http`
- Positioning: not tied to a single AI gateway; dry-run first
- `http get` / `http post` + timeout + dry fixture files + live
 `./spark-http` with `bearer` / `header` + `retries` / `backoff`
- **SPARK_BC Builder factory (init):** `--compile` Spark → `.sparkbc`
 with `TRAIN`/`STEP`/`TRAIN_STATUS`; bootstrap `--run-bc` dry;
 Spark-created init safetensors; published dumps + sha256. See
 [SPARK_BC Builder](SPARK_BUILDER.md). Dry ≠ trained.

## Next

| Track | What |
|-------|------|
| Extract | **done** (live + `--retries` / stub) |
| Ask | **done** (`--stream` / `ask stream`) |
| Eval | **done** — `expect equal` / `contains`; `make test-expect` |
| Escape | **done** — live `--allow-shell`; JS / C host FFI |
| Accounting | **done** — live wall-clock + run-level rollup |
| Builder | STEP→weights **done** (dry `weights.safetensors`); later owner train/eval growth — not claimed today |
| LSP | **done** — `tools/spark_lsp` + extension v0.2; [LSP.md](LSP.md) |
| Receptionist | Dry path **done** (`examples/receptionist.spark` + expect); live transfer/hold/hangup still **goal** |
| Releases | Cut GitHub Release tags from CHANGELOG (see RELEASE.md); Pages = human CF dashboard (no wrangler) |

## Done (rename)

| Track | What |
|-------|------|
| Rename | Public `sparklang-dev/sparklang` live. Site sparklang.dev. CLI remains `spark`. |

## Won't (near-term focus)

| Drop | Why |
|------|-----|
| MITM / pcap / browser automation as hero | Distracts from AI workflow language |
| Homegrown Electron/PyQt IDE as hero chrome | Prefer LSP for editor story; **IDE tree kept** (hard-delete plan **revoked** 2026-09-02) |
| Model-build as training product | Blueprint / eval sugar only |
| Production voice/telephony claim | Gaps remain (barge-in, EOU, SM, adapters) — gated demo only |
| Single-gateway-as-identity | Gateway optional; any OpenAI-compatible URL |

## Voice gaps (honest)

If not shipping soon, keep voice off the production claim list:

- Barge-in, EOU / silence detection, latency budget
- Call state machine: transfer / hold / hangup / VM / DTMF / STT retry
- Named STT / TTS / telephony adapters as stable contracts
- Concurrency model for multi-call

Dry `listen` / `speak` / gated PSTN remain demos. See [VOICE.md](VOICE.md).
