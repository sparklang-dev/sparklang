# What's real today (SparkLang)

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
| Public mirror stays current | **done** | One command: `scripts/sync-public-mirror.sh --push`. Regenerates the public tree from `main`, gates it against `scripts/public-mirror/forbid.txt`, and adds one fast-forward commit — no force-push. See [RELEASE.md](RELEASE.md) |
| Maintainer identity | **done** | GitHub org `sparklang-dev`; About page |
| Versioned releases + changelog | **done** | `CHANGELOG.md` + site `/CHANGELOG.html`; GitHub Release **0.6.2** (rename). Installer kit artifacts remain **0.6.0** until next packaging |
| Searchable name (SparkLang) | **done** | Hero / About / footers; public `sparklang-dev/sparklang`. CLI stays `spark` / `./spark-bootstrap` |
| Escape hatch (`.spark` → host) | **done (dry)** | `shell` / `run` allowlist dry-run fixtures; live gated exec = **next** |
| Escape hatch (host → `.spark`) | **done (Python)** | `from sparklang import run` (`python/sparklang/`); dry-run default, live opt-in; `./spark --embed` JSON handshake. JS / C FFI = **next** |
| `retrieve` / `embed` language ops | **done** | Dry fixtures + live `./spark-rag-http`; see LANGUAGE.md |
| Real `http get` / `post` | **done** | Dry fixture files + timeout; live `./spark-http` (curl). `bearer` / `header` + `retries` / `backoff` on documented failure classes |
| Typed `extract` + JSON-mode validate/retry | **partial** | Validation shipped: required vs `?` optional fields, `string`/`int`/`float`/`bool` types, top-level only, non-zero exit on a miss. Dry-run reads a real `fixture "PATH"`. Live extract and retry-on-miss = **next** |
| Cost/latency/token accounting | **done (hooks)** | Dry zeros; live prints `usage` when gateway returns it — never invents tokens |
| Streaming `ask` | **next** | Not shipped |
| Eval vs expectations (pass/fail) | **done** | `expect equal` / `expect contains` vs bound vars or `fixture "PATH"`; exit 0/1. Gate: `make test-expect` |
| Voice production telephony | **won't (soon)** | Gated demo + honest gaps in VOICE.md / ROADMAP — not sold as production |
| Packet capture / MITM / browser automation | **won't (focus)** | Still in LANGUAGE; de-emphasized on landing — prefer LSP + highlighting |
| Homegrown IDE as product chrome | **won't (focus) / keep tree** | Prefer LSP for editor story; language `ide` ops + IDE tree **kept**. Hard-delete OWNER-CONFIRM **revoked** 2026-09-02 (rename yes; delete no) |
| Model-build as training claim | **won't** | Blueprint / eval sugar only; demoted on landing |
| Production receptionist workflow | **goal** | `examples/receptionist_goal.spark` marked `[goal]` — dry sketch, not a live claim |

## Escape hatch (P0 design)

Without both directions, a DSL dies:

1. **From `.spark`:** `shell "echo …"` / `run "…"` — dry-run allowlist only
   (`echo` / `true` / `false`). Arbitrary exec refused offline. Live
   `--allow-shell` = **next**.
2. **Into `.spark`:** Python host embed is **shipped** —
   `from sparklang import run` (path or source string; dry-run default).
   Handshake: `./spark --embed`. Gate: `make test-host-embed`.
   JS / C FFI remain **next**.

## Worth using over script + gateway

Shipped enough to dry-demo RAG + ask + classify + http get/post (with
auth/retries) in one file. Still missing for a clear “shorter than
Python+gateway” win on production paths: streaming, live `extract`
against a model, and a dry-runnable receptionist that is more than a
`[goal]` sketch.

## Voice — honest

Optional `listen` / `speak` / `voice` / gated PSTN exist as language
surface and dry demos. **Not** production barge-in / EOU / SM transfer
/ named telephony adapters. See [VOICE.md](VOICE.md) gaps.

## Drops (product focus)

Landing and About de-emphasize: MITM, pcap, browser automation, homegrown
IDE *chrome as hero*, model-build-as-training. Prefer: language + dry-run +
playbooks + LSP / syntax highlighting + optional live gateway I/O.
**IDE tree stays in-repo** (delete revoked).

### Homepage honesty (critique v0.6.3)

Keep these off the hero; they belong here and in docs:

- **`model plan` is not training** — markdown plan only; train/build submit jobs.
- **HTTP auth / retries** for language `http get`/`post` = **done**
  (`bearer` / `header`, `retries` / `backoff`; see LANGUAGE.md).
- **Packet capture / MITM / browser** stay in LANGUAGE but are secondary vs
  train→eval (see “Also available” one-liner on the homepage).
- **Live train** — reference trainer ships **four** CPU methods:
  **`spark_distill_cpu`** (`weights.pt`), **`spark_pref_pack`**
  (`pref_pack.json` + `ranker.pt`), **`spark_playbook_fit`**
  (`playbooks.json` + `router.pt`), **`spark_faq_index`**
  (`faq_index.json` + `encoder.pt`). Same HTTP contract; select with
  POST `method` / `SPARK_TRAIN_METHOD`. Captures under
  `website/docs/examples/live-train-*.txt`.
  Do not claim LoRA or voice-GPU training on sparklang.dev.
- **Expectation pass/fail** is shipped (`expect equal` / `expect contains`).
  Homepage flagship is train → status → expect (`examples/train_eval.spark`).
  `model compare` remains an eval helper, not the hero loop.

## The real bar (goal, not claim)

One generic receptionist-style workflow (fallback + transfer), shorter
and easier to dry-test than Python+gateway — **no store/PII examples**.

→ `examples/receptionist_goal.spark` (`[goal]`). When syntax for transfer
lands, promote off the goal tag. Expectation pass/fail is shipped
(`expect equal` / `expect contains`).

## Related

- [ROADMAP.md](ROADMAP.md)
- [LANGUAGE.md](LANGUAGE.md)
- [RELEASE.md](RELEASE.md)
- [VOICE.md](VOICE.md)
