# Real coder lane — spark-code (2026-09-10)

Owner directive: "no tiny models and weights we need real ones the
best" — applied to spark-coder. The product code model is now the
self-hosted 30B on this box; the in-repo tiny coder is demoted to
reference implementation, with size-profile marketing removed from
code surfaces.

## Architecture

- **Product coder** — `python/sparklang/spark_coder/real_coder.py`:
  stdlib-only OpenAI-compatible client for the local
  **Qwen3-Coder-30B (Apache-2.0)** vLLM endpoint.
  - Default `http://127.0.0.1:8003`; override via env
    `SPARK_CODER_URL` or `--url`.
  - Offline / self-hosted: no API keys, no vendor calls.
  - Model id is discovered from `GET /v1/models` (no hardcoded
    served-name assumption).
  - **Fallback behavior:** none that fakes anything. The repo never
    starts/stops/restarts services. Endpoint down →
    `{"ok": false, "error": "coder_endpoint_down", ...}` and CLI
    exit **3** (`generate`, `eval_real`); `status` reports
    `"serving": false` plainly. Weights-missing reference path
    keeps exit 2.
- **CLI** (`tools/spark-code/cli.py`):
  - `generate` → endpoint by default; `--engine reference` uses the
    in-repo TinyCoder weights.
  - `status` → product endpoint (url/serving/model) + reference
    weights (present/trained/arch). No profile table.
  - `scales` subcommand **removed** (was the tiny/large profile
    table presentation).
  - `train` / `prove` / `tool-loop` unchanged in behavior; help
    text now factual (reference trainer).
- **Reference trainer** (`spark_coder/model.py`, `train.py`,
  `arch.py`, `tools_loop.py`): same pipeline, cleaned markers.
  `beats_claude` removed **entirely** from spark_coder output —
  code, JSON, arch, meta, and the regenerated checked-in artifacts
  under `models/spark-coder/` (incl. stripping the shared factory
  STEP checkpoint that `model_lab` still stamps for other lanes;
  `model_lab` itself untouched — voice/eval lanes out of scope).
- **Eval** — `tools/spark-code/eval_real.py`
  (`make spark-coder-eval-real`): 18 tasks, graded by execution.
  Generated code runs in a sandboxed subprocess (`python -I`,
  tempdir cwd, minimal env, RLIMIT_CPU/AS, 15 s timeout). Pass =
  asserts pass / exact stdout / expected exit code. Task mix:
  5 derived from `examples/fixtures/coder/` (exit-42 program,
  hello-spark stdout, opcode toggle, TRAIN/STEP arrow targets,
  sparkasm-themed explain) + 13 held-out (7 function-completion,
  3 bug-fix, 3 explain-code). temperature 0, one sample per task,
  pass@1 = passed/total. `--self-test` validates graders with
  canned completions (no model, CI-safe).

## Eval numbers (REAL runs only)

**Endpoint was DOWN at run time** (`vllm-qwen3-coder-30b` inactive;
only :8010 voice listening). Per policy this lane never starts
services, and the eval never fabricates numbers:

```
$ python3 tools/spark-code/eval_real.py   # exit 3
{"ok": false, "status": "skipped", "reason": "endpoint_down",
 "endpoint": "http://127.0.0.1:8003",
 "detail": "<urlopen error [Errno 111] Connection refused>", ...}
```

- **pass@1: not measured — no serving endpoint.** No number is
  claimed anywhere in this change.
- Harness mechanics proven without the model:
  `eval_real.py --self-test` → **5/5 checks pass** (right/wrong
  function-completion, program exit-code, right/wrong
  explain-code).
- Reproduce when serving: `make spark-coder-eval-real` → numbers
  land in `out/spark-coder/eval_real.json` (`summary.pass_at_1`,
  per-task rows with latency + grader detail).

## Gate results (this session)

| Gate | Result |
| ---- | ------ |
| `make test-spark-coder` | **12/12 OK** (9 existing + 3 new hermetic real-coder-lane tests); re-run green after rebase onto `origin/main` (`69e75c2`) |
| `make spark-coder-train` | green; prove **8/8 = 1.0** next-byte fixture accuracy, `trained=true` (pipeline proof, not product quality) |
| `./spark-code generate` (endpoint down) | plain `coder_endpoint_down`, exit 3 |
| `./spark-code generate --engine reference` | works from owned weights, no marker fields |
| `./spark-code status` | endpoint `serving: false` + reference weights present, exit 0 |
| `eval_real.py` (endpoint down) | `status: skipped`, exit 3, no numbers |
| `eval_real.py --self-test` | 5/5 pass |
| `beats_claude` in spark_coder code/artifacts | 0 remaining (only absence-assertions in tests/Makefile) |

## Truthful copy statements for the consolidated site/docs pass

Only these are true today; the site pass should reflect them
verbatim in spirit:

1. "Spark's product code model is a self-hosted Qwen3-Coder-30B
   (Apache-2.0) served locally — offline, no API keys, no vendor
   calls."
2. "The in-repo TinyCoder is a small reference implementation that
   proves the training pipeline end-to-end; it is not the product
   coder."
3. "Coding quality is measured by an execution-graded eval
   (`make spark-coder-eval-real`): generated code must actually
   run and pass tests in a sandboxed subprocess."
4. **No pass@1 number may be published yet** — the endpoint was
   down at authoring time. Publish only from a real
   `out/spark-coder/eval_real.json` produced while the endpoint
   serves.
5. Never claim "beats Claude" / any vendor comparison; never
   present tiny/large trainer dims as product size tiers. The old
   "Size profiles (tiny → xl)" table concept is gone from code
   surfaces and must not come back in copy.

## PR / merge state

- Branch `feat/real-coder`, rebased onto `origin/main` (`69e75c2`).
- PR: https://github.com/sparklang-dev/sparklang/pull/64
- CI `sparkbc` check pending at report-write time; merge per merge
  authority v3 when green (this report commit re-triggers a
  docs-only run).
