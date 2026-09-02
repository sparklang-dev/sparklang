# SparkLang adoption bar

Honest checklist against the critique: table stakes, escape hatch,
worth-using ops, voice honesty, what we drop, and the production-style
workflow goal. **Spark is not a Bifrost plugin** — gateway is optional
live I/O.

**Public name:** **SparkLang** (the Spark programming language).
Site: https://sparklang.dev/ · Source: https://github.com/sparklang-dev/sparklang

Not Apache Spark. Not AdaCore SPARK.

## Checklist

| Item | Status | Notes |
|------|--------|-------|
| Public repo + MIT license | **done** | `LICENSE`, `/LICENSE.txt` |
| Maintainer identity | **done** | GitHub org `sparklang-dev`; About page |
| Versioned releases + changelog | **done** | `CHANGELOG.md` + site `/CHANGELOG.html`; GitHub Release **0.6.2** (rename). Installer kit artifacts remain **0.6.0** until next packaging |
| Searchable name (SparkLang) | **done** | Hero / About / footers; **GitHub repo rename** `sparklang-dev/sparklang` → `sparklang-dev/sparklang` (OWNER-CONFIRM **yes** 2026-09-02). CLI stays `spark` / `./spark-bootstrap` |
| Escape hatch (`.spark` → host) | **done (dry)** | `shell` / `run` allowlist dry-run fixtures; live gated exec = **next** |
| Escape hatch (host → `.spark`) | **next** | `./spark --embed` stub JSON handshake; `import spark` FFI = **next** |
| `retrieve` / `embed` language ops | **done** | Dry fixtures + live `./spark-rag-http`; see LANGUAGE.md |
| Real `http get` / `post` | **next** | Auth/retries/timeouts — not `engine fetch` file://; design in ROADMAP |
| Typed `extract` + JSON-mode validate/retry | **partial** | Schema + dry fixture today; validate/retry loop = **next** |
| Cost/latency/token accounting | **done (hooks)** | Dry zeros; live prints `usage` when gateway returns it — never invents tokens |
| Streaming `ask` | **next** | Not shipped |
| Eval vs expectations (pass/fail) | **next** | `model compare` picks aliases; expectation harness = **next** |
| Voice production telephony | **won't (soon)** | Gated demo + honest gaps in VOICE.md / ROADMAP — not sold as production |
| Packet capture / MITM / browser automation | **won't (focus)** | Still in LANGUAGE; de-emphasized on landing — prefer LSP + highlighting |
| Homegrown IDE as product chrome | **won't (focus) / keep tree** | Prefer LSP for editor story; language `ide` ops + IDE tree **kept**. Hard-delete OWNER-CONFIRM **revoked** 2026-09-02 (rename yes; delete no) |
| Model-build as training claim | **won't** | Blueprint / eval sugar only; demoted on landing |
| Production receptionist workflow | **goal** | `examples/receptionist_goal.spark` marked `[goal]` — dry sketch, not a live claim |

## Escape hatch (P0 design)

Without both directions, a DSL dies:

1. **From `.spark`:** `shell "echo …"` / `run "…"` — dry-run allowlist only
   (`echo` / `true` / `false`). Arbitrary exec refused offline.
2. **Into `.spark`:** `./spark --embed` prints a stub handshake today;
   real Python/JS embed API is **next**.

## Worth using over script + gateway

Shipped enough to dry-demo RAG + ask + classify in one file. Still missing
for a clear “shorter than Python+gateway” win on production paths:
streaming, expectation evals, first-class HTTP, validate/retry `extract`,
and a dry-runnable receptionist that is more than a `[goal]` sketch.

## Voice — honest

Optional `listen` / `speak` / `voice` / gated PSTN exist as language
surface and dry demos. **Not** production barge-in / EOU / SM transfer
/ named telephony adapters. See [VOICE.md](VOICE.md) gaps.

## Drops (product focus)

Landing and About de-emphasize: MITM, pcap, browser automation, homegrown
IDE *chrome as hero*, model-build-as-training. Prefer: language + dry-run +
playbooks + LSP / syntax highlighting + optional live gateway I/O.
**IDE tree stays in-repo** (delete revoked).

## The real bar (goal, not claim)

One generic receptionist-style workflow (fallback + transfer), shorter
and easier to dry-test than Python+gateway — **no store/PII examples**.

→ `examples/receptionist_goal.spark` (`[goal]`). When syntax for transfer /
expectation eval lands, promote off the goal tag.

## Related

- [ROADMAP.md](ROADMAP.md)
- [LANGUAGE.md](LANGUAGE.md)
- [RELEASE.md](RELEASE.md)
- [VOICE.md](VOICE.md)
