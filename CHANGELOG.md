# Changelog

All notable user-facing releases of **SparkLang** (the Spark programming
language) are listed here. Site and installers track
`website/downloads/manifest.json`.

## 0.6.26 — 2026-09-08

- **Builder / SPARK_BC factory:** Spark compiles Spark to SPARK_BC
  (`selfhost/compile.spark` → `docs/examples/spark-self.sparkbc`)
  and emits **Spark-created init weights** from those bytes
  (`docs/examples/spark-self.init.safetensors`). Training is also
  in the binary: `TRAIN` `0x26` / `TRAIN_STATUS` `0x27` from
  `examples/spark_builder.spark` →
  `docs/examples/spark-builder.sparkbc`. Selfhost train seed:
  `selfhost/compile_train.spark` →
  `docs/examples/spark-selfhost-train.sparkbc`. Dump:
  `docs/examples/spark-builder-bc.txt`. Execute TRAIN from that
  file: `./spark-bootstrap --run-bc` (dry fixture + ARTIFACT
  marker; `trained=false`; not SGD). GAS `./spark --dry-run`
  runs train verbs from source; GAS does **not emit** `.sparkbc`
  and `./spark --run-bc` is **BLOCKED** (use bootstrap
  `--compile`). Page: [SPARK_BUILDER.md](docs/SPARK_BUILDER.md) /
  `/docs/spark-builder.html`. Honest: init, not trained. No
  imported weights. Emitting TRAIN ≠ a trained model. Later train
  aims to beat Claude. Companion `tools/spark-bc-dump/dump.py`.

## 0.6.25 — 2026-09-08

- **Model lab pipeline:** `model reverse` / `inspect` (local
  `config.json` + safetensors index, no tensor load), `model compile`
  (SPARK_BC plan for the `.spark` program), `model modify`
  (`keep_existing` + `keep_special_training` — attach only). Flagship
  `examples/model_lab.spark` also keeps SoT + `head abstain` so
  inventable facts still IDK. Companion `./spark-model-lab`. Gate:
  `make test-model-lab`. Not a new foundation LLM. Docs:
  [MODEL_LAB.md](docs/MODEL_LAB.md).

## 0.6.24 — 2026-09-08

- **Ground or IDK (default on):** inventable facts (prices, hours,
  weather, mayors, live IDs) must have SoT / `--sot-ok` /
  `SPARK_ASK_SOT_OK=1` or the runtime emits **I don't know.** — no
  gateway sample, no guess. `./spark-ask-http` links
  `bootstrap/ground_or_idk.c`. Head `live_ask` outer verify is **on
  by default** (`SPARK_ABSTAIN_OUTER_VERIFY=0` or
  `--no-outer-verify` / `--no-ground` to opt out). CPU train
  `load_pairs` refuses inventable assistant rows without `sot_ref`.
  Coding playbooks (`explain` / `reply with` / `ping`) and closed
  math (`what is 2+2`) still continue. Gate: `make test-ask-gateway`
  (`PASS dry_grounded_idk`) + `make test-abstain`.

## 0.6.23 — 2026-09-08

- **`spark_reply_pack`:** fifth CPU train method. Overlay **text +
  spoken** replies on a base that has **no voice**, or lock major
  behaviors (`greeting` / `hours` / `transfer` / `idk`). Inventable
  rows require `sot_ref` — missing SoT **fails loud** (never
  fabricate). Artifacts: `replies.json` + `gate.json` + `router.pt`.
  Not LoRA, not voice-GPU. Example:
  `examples/model_train_reply.spark`. Gate: `make test-train-http`
  (includes `tools/spark-train-ref/test_reply_pack.py`).

## 0.6.22 — 2026-09-02

- **Live `--allow-shell`:** `./spark --live --allow-shell` forks
  `./spark-shell`, which `execve`s allowlisted `echo` / `true` /
  `false` only. Never `system()`, never `/bin/sh -c`. Dry-run stays
  fixtures. Gate: `make test-shell`.
- **JS + C host FFI:** `js/sparklang` (`require`) and
  `host/c/sparklang.h` (`spark_run_path`). Python embed unchanged.
  `./spark --embed` advertises `api=python,js,c`. Gate:
  `make test-host-embed`.
- **Ask accounting:** live wall-clock `latency_ms` on
  `[accounting]`; run-level `[accounting-run]` via
  `spark-ask-http --rollup`. Dry zeros. Never invents tokens.
  Gate: `make test-ask-gateway` (`PASS rollup`).

## 0.6.21 — 2026-09-02

- **`lib-expect-after-extract` gate:** `make test-extract` / lib gate
  now require `./spark-expect`. Without the companion, extract still
  bound `-> person` but expect's fork failed and looked like a bind
  miss. Example: `examples/expect_after_extract.spark`. Gate:
  `PASS vm_expect_after_extract` / `PASS lib-expect-after-extract`.

## 0.6.20 — 2026-09-02

- **Live `extract` + retry-on-miss:** `./spark-extract --live` builds
  a JSON-only prompt, calls `./spark-ask-http`, validates against the
  inline schema, and retries with validation errors in the prompt
  (`--retries N`, default 2; optional `retries N` clause). Offline
  proof via `--stub-file` JSONL. `--model auto` refused. Asm passes
  `--model` from `model …`. Docs: LANGUAGE / ADOPTION_BAR / ROADMAP.
  Example: `examples/extract_live.spark`. Gate: `make test-extract`
  (`PASS live_stub_retry`).

## 0.6.19 — 2026-09-02

- **Streaming `ask` (SSE):** `./spark-ask-http --stream` sends
  `"stream":true`, prints token deltas as they arrive, accumulates
  for `--out`. Dry prints `stream=1` (no network). Language:
  `ask stream "…"` under `--live` (asm passes `--stream`).
  Docs: [docs/ASK_LIVE.md](docs/ASK_LIVE.md), ADOPTION_BAR /
  ROADMAP. Example: `examples/ask_stream.spark`. Gate:
  `make test-ask-gateway` (`PASS dry_stream`).

## 0.6.18 — 2026-09-02

- **Flagship no-invent example:** `examples/no_invent.spark` —
  SoT/`expect` first for inventable facts, `head abstain` +
  gated `head ask` for open asks (IDK + HALT). Honest scope:
  architecture prevents inventable open-decode, not “all
  hallucination forever.” Docs:
  [docs/ABSTAIN_HEADS.md](docs/ABSTAIN_HEADS.md),
  PROGRAMMING_GUIDE / LANGUAGE. Gate: `make test-abstain`.

## 0.6.17 — 2026-09-02

- **Abstain held-out eval + continue-SAMPLE:**
  `./spark-abstain --live eval` stratified train/held-out split,
  retrain on train fold, precision/recall/F1 on held-out
  (fixture/synthetic/host only — not production SOTA). Corpus
  seed ~105 rows. Continue path covered: HF `generate` when gate
  continues; `SPARK_ABSTAIN_SAMPLE_URL` OpenAI-compat SAMPLE;
  honest deferred note otherwise. Docs:
  [docs/ABSTAIN_HEADS.md](docs/ABSTAIN_HEADS.md). Gate:
  `make test-abstain` (optional kl3m eval if smoke dir present).

## 0.6.16 — 2026-09-02

- **Abstain real-dim corpus path:** curated
  `examples/fixtures/abstain/corpus_seed.jsonl` (answer vs abstain
  + reasons), schema/`validate-corpus`, synthetic backbone export
  at LM widths (default 768) for dim-matched train/ask without
  claiming HF quality. Optional env-gated HF smoke
  (`tools/spark-abstain/hf_export_train_smoke.sh`,
  `SPARK_ABSTAIN_HF=1` + local model, `local_files_only` /
  offline — no CI downloads). Docs:
  [docs/ABSTAIN_HEADS.md](docs/ABSTAIN_HEADS.md),
  `examples/fixtures/abstain/README.md`. Gate: `make test-abstain`.

## 0.6.15 — 2026-09-02

- **Abstain `/spark_hidden` sidecar:** real HF FastAPI/uvicorn
  export beside stock vLLM
  (`tools/spark-abstain/spark_hidden_sidecar.py`), shared
  OpenAI-adjacent contract
  (`python/sparklang/abstain/spark_hidden.py`), hardened client
  (`SPARK_ABSTAIN_VLLM_URL` / `TIMEOUT` / `TOKEN`). Stub kept for
  CI. Extra: `pip install -e 'python/[sidecar]'`. Docs:
  [docs/ABSTAIN_HEADS.md](docs/ABSTAIN_HEADS.md). Gate:
  `make test-abstain` (HTTP mocked; no GPU).

## 0.6.14 — 2026-09-02

- **Abstain export→train (dim-matched):** `./spark-abstain --live export`
  writes JSONL hiddens from an explicit HF backbone (`--model`) or a
  CPU **toy** backbone (`--hidden-dim`, CI). Train on those rows so
  `hidden_dim` matches ask. Fixtures:
  `labels_text.jsonl`, `labels_exported.jsonl` (dim 16). Optional
  `tools/spark-abstain/spark_hidden_stub.py` for the `/spark_hidden`
  contract. Docs: [docs/ABSTAIN_HEADS.md](docs/ABSTAIN_HEADS.md)
  (wired from README / PROGRAMMING_GUIDE / site). Gate:
  `make test-abstain`.

## 0.6.13 — 2026-09-02

- **No Bifrost-style model alias pick:** dry-run / `use auto` no longer
  invents `fast`|`code` from task text. `use auto` keeps the prior
  configured model (`spark.toml` / earlier `model` line). Live
  `./spark-ask-http --model auto` is refused — pass an explicit HF id /
  path / configured name. Docs and catalogs scrubbed of “Pick model
  alias per task” / bootstrap alias roulette copy.

## 0.6.12 — 2026-09-02

- **Abstain HF hooks:** live `head ask` SELECT-before-SAMPLE with real
  `p(abstain|h)` from last-token hidden (file / HF transformers /
  best-effort vLLM `/spark_hidden`). Stub path unchanged
  (`SPARK_ABSTAIN_STUB=1`). Refuses gateway aliases (`auto`/`code`/
  `fast`, …) — explicit HF path or `org/name` only. Optional
  `pip install -e 'python/[hf]'`. Docs: live generate path in
  [docs/ABSTAIN_HEADS.md](docs/ABSTAIN_HEADS.md). Gate:
  `make test-abstain` (mocks HF; no 27B download).

## 0.6.11 — 2026-09-02

- **Abstain / IDK heads:** language ops `head abstain|train|attach|ask`
  with SELECT-before-SAMPLE gate. Internal = linear/MLP probe on frozen
  backbone last-hidden; external = same math as sidecar. Companion
  `./spark-abstain` (dry fixtures + CPU train/attach). Docs:
  [docs/ABSTAIN_HEADS.md](docs/ABSTAIN_HEADS.md). Not LoRA; no fake
  weights in dry-run. Gate: `make test-abstain`.
- Examples: `head_abstain.spark`, `head_ask.spark`, `head_train.spark`,
  `head_attach.spark`, `head_abstain_external.spark`.

## 0.6.10 — 2026-09-02

- **Python host embed:** `from sparklang import run` under
  `python/sparklang/` runs a `.spark` path or source string via the
  `spark` CLI (dry-run default; `live=True` opt-in). Returns stdout /
  stderr / exit code; missing binary or path fails loud.
- `./spark --embed` handshake advertises `api=python` (JS / C FFI
  remain `[next]`).
- Example: `examples/python/host_embed.py`. Gate: `make test-host-embed`.

## 0.6.9 — 2026-09-02

- **Language `method "…"`** on `model train` / `model build`
  (`spark_distill_cpu` | `spark_pref_pack` | `spark_playbook_fit` |
  `spark_faq_index`).
- Live GAS forwards the statement via
  `./spark-train-http --spark-line` (method / dataset / base / out).
- Live `model status "job-id"` polls that job id — **not** hardcoded
  `job-dry-001`.
- Dry fixtures fail loud on unknown method or unknown status job id.

## 0.6.8 — 2026-09-02

- **Fourth CPU train method:** **`spark_faq_index`** — FAQ corpus +
  dual-encoder retriever → `faq_index.json` + `encoder.pt`. Not LoRA /
  not a marker stub. Same HTTP `method` field as distill / pref /
  playbook.
- Example: `examples/model_train_faq.spark`.
- Docs / hero list four methods honestly.

## 0.6.7 — 2026-09-02

- **`http get` / `http post` auth + retries:** `bearer "TOKEN"`,
  `header "Name: value"`, `retries N`, `backoff MS` (keep existing
  `timeout`). Live curl sends real headers; retries only on documented
  transport exits (7/28/35/52/56) and HTTP 408/429/5xx subset. Dry-run
  still fixtures-only (missing fixture → exit 1; no fake network).
- Examples: `examples/http_get_auth.spark`,
  `http_get_auth_live.spark`, `http_get_retries_live.spark`.
- Gate: `make test-http` / `SPARK_HTTP_LIVE=1` covers bearer + 503
  retry proof.

## 0.6.6 — 2026-09-02

- **Three CPU train methods** (not LoRA) behind the same HTTP contract:
  - **`spark_distill_cpu`** — reply-class student → `weights.pt`
  - **`spark_pref_pack`** — preference pairs + ranker →
    `pref_pack.json` + `ranker.pt`
  - **`spark_playbook_fit`** — intent→playbook router →
    `playbooks.json` + `router.pt`
- Select via POST `method`, companion `--method`, or
  `SPARK_TRAIN_METHOD` (default `spark_distill_cpu`). Reference trainer
  `tools/spark-train-ref/` dispatches all three on CPU.
- Live captures:
  `website/docs/examples/live-train-capture.txt`,
  `website/docs/examples/live-train-methods-capture.txt`.
- Hero / What's real today list the three methods honestly.
- Examples: `examples/model_train_pref.spark`,
  `examples/model_train_playbook.spark`.

## 0.6.5 — 2026-09-02

- **Custom train proof:** reference trainer runs **`spark_distill_cpu`**
  — tiny PyTorch student on CPU that mimics teacher replies from chat
  JSONL. Writes real `weights.pt` (+ checkpoint). Not LoRA / not HF PEFT
  / no voice GPU. Live capture:
  `website/docs/examples/live-train-capture.txt` via
  `./spark --live examples/model_train.spark`.
- **Hero:** “Train specialists — CPU distill, not LoRA” (honest about
  what the reference path trains).
- **`expect` form on homepage / Learn / examples:** prefer
  `expect contains NAME fixture "PATH"` (fail-loud fixtures) — one form
  for the flagship snippets.
- **`expect equal` / `expect contains`:** assert a bound name against a
  literal or `fixture "PATH"`. Pass exits **0**; fail exits **1** with
  the reason (missing fixture / unknown name / mismatch). Wired in GAS
  (`./spark-expect`), bootstrap, and SPARK_BC `0x25`. Gate:
  `make test-expect`. Examples: `examples/expect_pass.spark`,
  `examples/expect_fail.spark`.
- **Flagship train→status→expect:** `model train` / `model status` now
  bind `->` names in GAS dry-run so `expect` can assert against job and
  status JSON. Homepage / Learn use `examples/train_eval.spark` (exit 0);
  fail path `examples/train_eval_fail.spark` (exit 1).
- **Reference trainer:** `tools/spark-train-ref/` (`server.py` +
  `distill_cpu.py`) implements the companion HTTP contract.

## 0.6.4 — 2026-09-02

- **`http get` / `http post`:** first-class ops with `timeout` and
  dry-run **fixture files** (fail loud if missing). Live companion
  `./spark-http` (curl). Auth / retries still next — not claimed.
  Examples: `examples/http_get.spark`, `examples/http_post.spark`.
  Gate: `make test-http`.

## 0.6.3 — 2026-09-02

- **Model training pillar:** `model train` / `model build` submit real
  training jobs; `model status` polls artifacts. Dry-run fixtures under
  `examples/fixtures/train/`. Live companion `./spark-train-http`
  (`SPARK_TRAIN_BACKEND=http|local-yield`). Docs:
  `docs/MODEL_TRAINING.md`.
- **`model plan`** replaces blueprint-only `model build` markdown export.
- Analyze / compare / improve stay eval helpers.

## 0.6.2 — 2026-09-02

- **Rename:** public GitHub repo `sparklang-dev/spark` →
  `sparklang-dev/sparklang` (OWNER-CONFIRM). Site remains
  https://sparklang.dev/. Docs/site/README/About/RELEASE/ADOPTION_BAR
  clone URLs updated.
- **CLI:** binary / bootstrap names stay `spark` and `./spark-bootstrap`
  (no overnight break). Product identity is **SparkLang**.
- **IDE:** tree **kept** (hard-delete OWNER-CONFIRM revoked). Editor story
  still prefers LSP + highlighting; language `ide` ops unchanged.
- Installer kit filenames / hashes remain **0.6.0** until the next
  packaging pass (no kit rebuild in this rename land).

## 0.6.0 — 2026-09-02

- Runtime / installer kit **0.6.0** (see Downloads manifest).
- Language + dry-run runtime: `.spark` programs, fixtures, compile/BC path,
  IDE language ops, playbooks.
- Optional live `ask` via any OpenAI-compatible `AI_GATEWAY_URL` (not required
  for the default dry-run story).
- Optional surfaces: voice/PSTN (gated), browser/MITM, network capture.
- `model analyze` / `compare` / `improve` = eval helpers;
  `model train` / `build` / `status` = real jobs (see MODEL_TRAINING.md);
  `model plan` = optional markdown.

## Earlier

See [GitHub releases](https://github.com/sparklang-dev/sparklang/releases) and
commit history on `main` for prior notes.
