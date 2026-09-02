# AI coding playbooks

Describe the task, pick a playbook, write almost no code.

## Quick start

1. Start your script with `include "lib/ai.spark"` (sets `use auto`).
2. Copy a block from `lib/playbooks.spark` or a fixture under
   `bootstrap/fixtures/playbooks/`.
3. Or pick one in the **website playground** (Preset → AI playbooks) or
   insert a `spark-playbook-*` snippet in Cursor/`make ide`.
4. Dry-run offline: `./spark-bootstrap --dry-run my_task.spark`
5. Verify goldens: `make test-ai-playbooks`

The playground **lists and loads** playbook fixtures only. It has no WASM
runtime — **Run dry-run** on a playbook fails loud with a download link
and does not invent output. Catalog JSON:
`website/data/playbooks-catalog.json` (`make playbooks-catalog`).

Live gateway wiring is unchanged — see [ASK_LIVE.md](ASK_LIVE.md).
Model-focused overview: [AI_MODELS.md](AI_MODELS.md).

## Auto model selection

With `use auto` (or `include "lib/ai.spark"`), the bootstrap VM picks:

- **`fast`** — explain, summarize, classify+reply, general chat
- **`code`** — fix tests, add APIs, refactor/rename, write tests, debug errors,
  review/builder/tool lines, or prompts that mention files and patches

Dry-run prints `[model] auto→fast` or `[model] auto→code` before each AI call.
Override anytime: `use code` or `use fast`.

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
include "lib/ai.spark"
let failure "AssertionError: expected 3 got 2 in test_add"
ask "Fix this test failure: {failure}" -> fix
print fix
```

## Deferred

- Training / fine-tune pipeline (not this slice)
- SPARK_BC / bytecode vm.c migration for auto pick (Phase 4–6 track)
- First-class `retrieve` / `embed` language ops — **shipped** (see
  [AI_MODELS.md](AI_MODELS.md) + [LANGUAGE.md](LANGUAGE.md));
  dry fixtures + `make test-rag-gateway`

Optional live gateway: `./spark-ask-http` resolves `use auto` / `--model auto` to
`fast`\|`code` before the request (same heuristics as bootstrap dry-run).
Gate: `make test-ask-gateway`.
