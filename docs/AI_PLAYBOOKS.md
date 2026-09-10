# AI coding playbooks

Describe the task, pick a playbook, write almost no code.

## Quick start

1. Start with an **explicit** model line (`model "…"` HF id / path /
 configured name) or `include "lib/ai.spark"` (docs only — set model).
2. Copy a block from `lib/playbooks.spark` or a fixture under
 `bootstrap/fixtures/playbooks/`.
3. Or pick one in the **website playground** (Preset → AI playbooks) or
 insert a `spark-playbook-*` snippet in the local editor / `make ide`.
4. Dry-run offline: `./spark-bootstrap --dry-run my_task.spark`
5. Verify goldens: `make test-ai-playbooks`

The playground **lists and loads** playbook fixtures only. It has no WASM
runtime — **Run dry-run** on a playbook fails loud with a download link
and does not invent output. Catalog JSON:
`website/data/playbooks-catalog.json` (`make playbooks-catalog`).

Live gateway wiring is unchanged — see [ASK_LIVE.md](ASK_LIVE.md).
Model-focused overview: [AI_MODELS.md](AI_MODELS.md).

## Model line (explicit)

SparkLang is **not** a the AI gateway plugin. There is **no** per-task alias
roulette (`auto` inventing gateway aliases from task text).

- Set `model "hf-org/name"` / `model "path/to/checkpoint"` / your
 configured gateway model string.
- `use auto` keeps the **prior** configured line (`spark.toml` /
 earlier `model`) and prints `[model] prior … (no alias pick)`.
- Dry-run never invents a model id from prompt text.

## Playbook catalog

| Playbook | Fixture | Typical prompt shape |
| --- | --- | --- |
| `explain_code` | `explain_code.spark` | Explain this code in one sentence |
| `fix_test_failure` | `fix_test_failure.spark` | Fix this test failure: … |
| `add_api_endpoint` | `add_api_endpoint.spark` | Add a GET /health API endpoint … |
| `refactor_rename` | `refactor_rename.spark` | Refactor: rename foo to bar … |
| `write_unit_test` | `write_unit_test.spark` | Write a unit test for … |
| `debug_error_message` | `debug_error_message.spark` | Debug this error message: … |
| `classify_and_reply` | `classify_and_reply.spark` | classify Intent … then ask reply |
| `review_and_suggest` | `review_and_suggest.spark` | review path … then ask for fix |
| `pipeline_summarize_explain` | `pipeline_summarize_explain.spark` | pipeline summarize \| explain |

## Example — fix a failing test

```spark
model "fixtures/tiny-lm"
let failure "AssertionError: expected 3 got 2 in test_add"
ask "Fix this test failure: {failure}" -> fix
print fix
```

## Deferred

- Training / fine-tune pipeline (not this slice)
- First-class `retrieve` / `embed` language ops — **shipped** (see
 [AI_MODELS.md](AI_MODELS.md) + [LANGUAGE.md](LANGUAGE.md));
 dry fixtures + `make test-rag-gateway`

Optional live gateway: `./spark-ask-http --model <explicit-id> …`.
Gate: `make test-ask-gateway`.
