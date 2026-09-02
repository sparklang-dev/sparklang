# Changelog

All notable user-facing releases of **SparkLang** (the Spark programming
language) are listed here. Site and installers track
`website/downloads/manifest.json`.

## 0.6.5 — 2026-09-02

- **`expect equal` / `expect contains`:** assert a bound name against a
  literal or `fixture "PATH"`. Pass exits **0**; fail exits **1** with
  the reason (missing fixture / unknown name / mismatch). Wired in GAS
  (`./spark-expect`), bootstrap, and SPARK_BC `0x25`. Gate:
  `make test-expect`. Examples: `examples/expect_pass.spark`,
  `examples/expect_fail.spark`.
- **Flagship train→status→expect:** `model train` / `model status` now
  bind `->` names in GAS dry-run so `expect` can assert against job and
  status JSON. Homepage / Learn use `examples/train_eval.spark` (exit 0);
  fail path `examples/train_eval_fail.spark` (exit 1). Live train still
  needs your trainer at `SPARK_TRAIN_URL` — dry-run only proves the path.
- **Reference trainer:** `tools/spark-train-ref/server.py` implements the
  companion HTTP contract; live capture at
  `website/docs/examples/live-train-capture.txt`.

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
