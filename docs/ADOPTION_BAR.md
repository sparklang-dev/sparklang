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
| Escape hatch (`.spark` → host) | **done** | `shell` / `run` allowlist dry-run fixtures; live gated exec via `./spark --live --allow-shell` + `./spark-shell` (`execve`, never `system()`) |
| Escape hatch (host → `.spark`) | **done** | Python `from sparklang import run`; JS `require('./js/sparklang')`; C `host/c/sparklang.h`. Dry-run default, live opt-in. `./spark --embed` handshake. Gate: `make test-host-embed` |
| `retrieve` / `embed` language ops | **done** | Dry fixtures + live `./spark-rag-http`; see LANGUAGE.md |
| Real `http get` / `post` | **done** | Dry fixture files + timeout; live `./spark-http` (curl). `bearer` / `header` + `retries` / `backoff` on documented failure classes |
| Typed `extract` + JSON-mode validate/retry | **done** | Dry fixture validation unchanged. Live: `./spark-extract --live` via `spark-ask-http`, schema validate, `--retries N` (default 2) on miss; offline `--stub-file` proves retry. `--model auto` refused |
| Cost/latency/token accounting | **done** | Dry zeros; live wall-clock `latency_ms` + gateway `usage` when present; run-level `[accounting-run]` rollup. Never invents tokens |
| Streaming `ask` | **done** | Companion `./spark-ask-http --stream` (SSE deltas + `--out` accumulate); language `ask stream "…"` under `--live`; dry gate `stream=1` |
| Eval vs expectations (pass/fail) | **done** | `expect equal` / `expect contains` vs bound vars or `fixture "PATH"`; exit 0/1. Gate: `make test-expect` |
| Voice production telephony | **won't (soon)** | Gated demo + honest gaps in VOICE.md / ROADMAP — not sold as production |
| Packet capture / MITM / browser automation | **won't (focus)** | Still in LANGUAGE; de-emphasized on landing — prefer LSP + highlighting |
| Homegrown IDE as product chrome | **won't (focus) / keep tree** | Prefer LSP for editor story; language `ide` ops + IDE tree **kept**. Hard-delete OWNER-CONFIRM **revoked** 2026-09-02 (rename yes; delete no) |
| Model-build as training claim | **won't** | Blueprint / eval sugar only; demoted on landing |
| SPARK_BC Builder factory | **done (multi-outer SGD)** | Spark → `--compile` → `.sparkbc` with `TRAIN`/`STEP`/`TRAIN_STATUS`; `--run-bc` TRAIN dry + STEP multi-outer CPU SGD (bootstrap or GAS); `checkpoint.json` loss curve; post-STEP `trained=true` / `not_sgd=false` when grads apply. Serve optional MLP0. GAS wrappers **implemented**. **Not beat Claude.** Page: [SPARK_BUILDER.md](SPARK_BUILDER.md) / `/docs/spark-builder.html` |
| Production receptionist workflow | **goal** | `examples/receptionist_goal.spark` marked `[goal]` — dry sketch, not a live claim |

## Escape hatch (P0 design)

Without both directions, a DSL dies:

1. **From `.spark`:** `shell "echo …"` / `run "…"` — dry-run allowlist
   fixtures (`echo` / `true` / `false`). Arbitrary exec refused.
   Live: `./spark --live --allow-shell` forks `./spark-shell` which
   `execve`s the resolved binary (never `system()`, never `/bin/sh -c`).
2. **Into `.spark`:** Python / JS / C host embed is **shipped** —
   `from sparklang import run`, `require('./js/sparklang')`,
   `spark_run_path()` (path; dry-run default).
   Handshake: `./spark --embed`. Gate: `make test-host-embed`.

## Worth using over script + gateway

Shipped enough to dry-demo RAG + ask + classify + http get/post (with
auth/retries), streaming `ask`, and live `extract` (validate +
retry) in one file. Still missing for a clear “shorter than
Python+gateway” win on production paths: a dry-runnable
receptionist that is more than a `[goal]` sketch.

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
- **Live train** — reference trainer ships **five** CPU methods:
  **`spark_distill_cpu`** (`weights.pt`), **`spark_pref_pack`**
  (`pref_pack.json` + `ranker.pt`), **`spark_playbook_fit`**
  (`playbooks.json` + `router.pt`), **`spark_faq_index`**
  (`faq_index.json` + `encoder.pt`), **`spark_reply_pack`**
  (`replies.json` + `gate.json` + `router.pt` — voice+text overlay
  on text-only bases, behavior lock, inventable → SoT or IDK).
  Same HTTP contract; select with POST `method` / `SPARK_TRAIN_METHOD`.
  Captures under `website/docs/examples/live-train-*.txt`.
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
