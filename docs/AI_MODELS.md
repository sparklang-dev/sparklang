# SparkLang and AI models

**SparkLang** (the Spark programming language) is a **language and runtime**
for creating and modifying AI workflows efficiently — not a pile of training
scripts and SDK glue, and **not** a Bifrost plugin. Model work, optional live
gateway routing, retrieval (`embed` / `retrieve`), and AI coding live in
plain `.spark` files you can diff, dry-run, and ship.

**Default story:** dry-run / offline / no keys. Live `ask` / `embed` /
`retrieve` via gateway env is **optional** (`./spark --live`).

**Related:** [SPARK_BUILDER.md](SPARK_BUILDER.md) (full factory E2E —
SPARK_BC vs weights; `TRAIN` `0x26` / `STEP` `0x28` /
`TRAIN_STATUS` `0x27`; sha256 table; GAS BLOCKED; dry ≠ trained) ·
[SPARK_BC.md](SPARK_BC.md) (bytecode ISA) ·
[MODEL_LAB.md](MODEL_LAB.md) (reverse / compile / modify) ·
[MODEL_TRAINING.md](MODEL_TRAINING.md) (train jobs) ·
[ABSTAIN_HEADS.md](ABSTAIN_HEADS.md) (IDK / abstain heads) ·
[MODEL_ANALYSIS.md](MODEL_ANALYSIS.md) (eval methodology) ·
[AI_PLAYBOOKS.md](AI_PLAYBOOKS.md) (coding playbooks) ·
[LANGUAGE.md](LANGUAGE.md) (full statement reference) ·
[ASK_LIVE.md](ASK_LIVE.md) (optional live gateway `ask`) ·
[ADOPTION_BAR.md](ADOPTION_BAR.md) (done/next/won't)

## What Spark means for model create / modify

| Goal | Spark today | Honest limits |
|------|-------------|---------------|
| **Train / build** real jobs | `model train` / `model build` → job; `model status` | Dry fixtures; live `./spark-train-http`. **`spark_reply_pack`** overlays voice+text on text-only bases and refuses inventable rows without SoT — see [MODEL_TRAINING.md](MODEL_TRAINING.md) |
| **Reverse / inspect** | `model reverse` / `model inspect` → architecture JSON | Local `config.json` + index names only; [MODEL_LAB.md](MODEL_LAB.md) |
| **Compile program** | `model compile "….spark" into "….sparkbc"` | SPARK_BC of the **program**, not a transformer compiler |
| **Builder from SPARK_BC** | `--compile` Spark → `.sparkbc` (incl. `0x26`/`0x28`/`0x27`); dump; emit init weights; bootstrap `--run-bc` dry train | Spark-created **init**, not trained; GAS emit/`--run-bc` **BLOCKED**; STEP→weights **implemented** (dry); later train aims to beat Claude; [SPARK_BUILDER.md](SPARK_BUILDER.md) |
| **Modify existing** | `model modify keep_existing …` | Attach adapters/heads; **never** delete special training |
| **Abstain / IDK heads** | `head abstain|train|attach|ask` | Probe on frozen local LLM; SELECT before SAMPLE; [ABSTAIN_HEADS.md](ABSTAIN_HEADS.md) |
| **Analyze** reachable models | `model analyze "…" -> report` | Dry-run = fixtures under `examples/fixtures/models/`; not live leaderboards |
| **Compare** on your suite | `model compare […] on suite "…" -> comparison` | Same fixture metrics; optional `make model-probe` for read-only discovery |
| **Improve** toward a preference | `model improve from report prefer quality\|speed\|cost\|local -> blueprint` | Heuristic; review before train |
| **Plan** markdown export | `model plan blueprint into "out/better-model.md"` | Markdown only — not weights |
| **Name a concrete model** | `model "/path/or/org/name"` / attach manifest | Explicit path or hub id only — **no** auto/code/fast alias pick, no dry-run invent |
| **AI coding** with less boilerplate | `include "lib/playbooks.spark"`, `review` / `builder` / `implement` | Playbooks = bootstrap VM; GAS `./spark` catches up on self-host track |
| **Call models live (optional)** | `ask "…" -> reply` with `./spark --live` | Needs `AI_GATEWAY_URL` + key; companion `./spark-ask-http` |
| **Embed / retrieve** | `embed "…" -> vec`, `retrieve "…" from project "docs" -> hits` | Dry fixtures; live `./spark-rag-http` |
| **Probe gateway creds** | `ask probe` / `gateway probe` | Dry gateway probe check; 401 → credential unavailable |

**“All models”** = configured model ids + discovered local vLLM listeners
(read-only) — not every model on the internet. See [MODEL_ANALYSIS.md](MODEL_ANALYSIS.md).

Example train (dry-run):

```spark
model train dataset "examples/fixtures/train/dataset.jsonl" base "fixture-base" out "out/train/job-dry-001" backend "http" -> job
model status "job-dry-001" -> status
```

Example eval helpers (dry-run):

```spark
model "fixtures/tiny-lm"

model analyze "fixtures/tiny-lm" -> report

model compare ["fixtures/tiny-lm", "fixtures/other-lm"]
  on suite "examples/eval_suite.json" -> comparison

model improve from report prefer quality -> blueprint

model plan blueprint into "out/my-model.md"
```

```bash
./spark --dry-run examples/model_improve.spark
```

## Dry-run today (no keys, no network) — default

Default `./spark --dry-run` and `make test` stay **offline**:

- **Model ops** — fixture JSON from `examples/fixtures/models/` and
  `examples/eval_suite.json`; banner says numbers are not live Elo scores
- **`ask` / `classify` / `extract` / `embed` / `retrieve`** — heuristic
  stubs / fixtures (`examples/fixtures/rag/` for RAG)
- **`use auto`** — keeps prior configured model; prints
  `[model] prior … (no alias pick)` — never invents gateway aliases
- **Playbooks** — goldens under `bootstrap/fixtures/playbooks/`;
  `make test-ai-playbooks`
- **IDE** — `ide new|open|save|run|buffer|ask|show` + keymap traces under
  `out/ide/` (PPM paint wire, not product Electron)

Dry-run is the primary loop for CI, learning, and readable diffs **before**
you spend on live inference.

## Optional live gateway (`./spark --live`)

When you opt in with `./spark --live`, Spark forks companions against an
OpenAI-compatible base URL (and rag-gateway for retrieve):

| Integration | Role | Env / companion |
|-------------|------|-----------------|
| **OpenAI-compatible gateway** (`AI_GATEWAY_URL`) | Chat + embeddings with an **explicit** model id (HF / path / configured string). Bifrost is one optional backend, not a Spark requirement. | **`SPARK_GATEWAY_KEY`** preferred; `OPENAI_API_KEY` wire-compat only; `./spark-ask-http` / `./spark-rag-http --embed` |
| **rag-gateway** (`RAG_GATEWAY_URL`) | `POST /v1/retrieve` (project + audience; CRAG on operator/cursor) | Default `:4620`; `RAG_GATEWAY_API_KEY` or `SPARK_GATEWAY_KEY`; `./spark-rag-http --retrieve` |
| **Model probe** (optional) | Read-only configured models + local vLLM port discovery | `make model-probe`; `SPARK_ALLOW_NET=1` |
| **Encrypt-to-model** | Seal prompt; gateway decrypts at model boundary | [ENCRYPT_GATEWAY.md](ENCRYPT_GATEWAY.md); `./spark-enc-gateway` |
| **Public gateway probe** | Credential check only | a gateway probe credential; HTTP 401 → stop, no routing verdict |

Pass an **explicit** model id in `.spark` / `--model` — never invent one
from task-text heuristics, and do not treat Spark as a Bifrost alias
picker. Inventable live prompts **IDK** unless `--sot-ok`
(see [ASK_LIVE.md](ASK_LIVE.md)).

```bash
export AI_GATEWAY_URL=http://127.0.0.1:4000
export SPARK_GATEWAY_KEY=sk-…   # never commit; preferred over OPENAI_API_KEY
./spark --live examples/ask_live.spark
./spark --live examples/ask_live_explicit.spark
./spark --live examples/retrieve_embed_live.spark
# Offline proof (no key / no network):
make test-ask-gateway
make test-rag-gateway
```

## Retrieval stack (shipped)

First-class language ops — not a fake roadmap:

| Layer | Integration | Spark statement |
|-------|-------------|-----------------|
| **Embeddings** | Gateway `embed` / `embed-rag` → `POST /v1/embeddings` | `embed "…" [model embed-rag\|embed] -> vec` |
| **RAG** | rag-gateway `POST /v1/retrieve` | `retrieve "…" from project "…" [audience …] [top_k N] -> hits` |
| **CRAG** | Gateway-side for `operator` / `cursor` audiences | Present in retrieve JSON `crag`; compose with `ask` for answers |
| **Dry fixtures** | `examples/fixtures/rag/` + `bootstrap/dry_rag.c` | `make test-rag-gateway` offline |

Governed ledger / product-specific projects stay outside public Spark
examples — use generic `project "docs"` in docs and fixtures.

## AI coding + Spark IDE

**Less code:** set an explicit `model "…"` (or `include "lib/ai.spark"`
and add one); copy a playbook from
[AI_PLAYBOOKS.md](AI_PLAYBOOKS.md) instead of hand-rolling SDK loops.

**Readable diffs:** one `.spark` file per workflow — `pipeline`, `classify`,
`extract`, `review`, `builder`, `implement` — not scattered Python modules.

**Verified IDE surface** ([IDE.md](IDE.md)): terminal-first `ide` ops + optional
interim Cursor workspace (`make ide`). Not Electron / not PyQt product chrome.

Voice (`listen` / `speak` / `voice { … }`) remains in the language for
speech pipelines — it is an **optional** surface, not primary positioning. See
[VOICE.md](VOICE.md).

## What Spark is not

- Not a Bifrost plugin — gateway is optional live backend for `ask` /
  `embed` / `retrieve`
- Not Apache Spark / AdaCore SPARK
- Not a replacement narrative for “throw away Python + OpenAI SDK” — Spark
  complements gateways and existing stacks with a reviewable language surface
- Train jobs need a configured backend — dry-run never starts GPU work
- Not in-process CRAG — grade/retry stay on rag-gateway; Spark surfaces
  `crag` JSON from `retrieve` and composes with `ask`
- Not a vendor voice-product codebase — Spark stays a general AI language

## Contributor internals

Bytecode VM, self-host, and assembler tiers are **contributor-facing** only:
[SELF_HOST.md](SELF_HOST.md), [SPARK_BC.md](SPARK_BC.md), `website/docs/self-host.html`.
User-facing model docs stay in this file and [MODEL_ANALYSIS.md](MODEL_ANALYSIS.md).
