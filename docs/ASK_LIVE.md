# Spark optional live ask (`AI_GATEWAY_URL`)

`--dry-run` never touches the network — that is the **default** Spark story.
Live `ask` / `generate` is **optional**: it requires `--live` and the companion
`./spark-ask-http`.

**Honesty:** this document covers the OpenAI-compatible live `ask` path only —
not a claim of full IDE chrome, full ES, or Google.com browsing. Spark is a
**language + runtime**; it is **not** a Bifrost plugin. Bifrost (or any other
OpenAI-compatible gateway) is one optional backend when you set
`AI_GATEWAY_URL`.

## Env

| Var | Role |
|-----|------|
| `AI_GATEWAY_URL` | OpenAI-compatible base (common local default `http://127.0.0.1:4000`) |
| `SPARK_GATEWAY_KEY` | **Preferred** gateway Bearer (`sk-*` / `sk-bf-*`) |
| `OPENAI_API_KEY` | Wire-compat Bearer name only — not an OpenAI.com primary CTA |

Prefer gateway **aliases** (`fast`, `code`, `best`, `auto`, …) — not vendor
model strings. `use auto` / `--model auto` resolves to `fast` or `code`
inside `./spark-ask-http` (same heuristics as bootstrap dry-run) before
the request — never sends literal `auto` to the gateway.

Never route Spark compute to voice / `:8010` / reserved voice GPU.

## Offline dry gate (CI / no key)

```bash
make spark-ask-http
./spark-ask-http --dry --model fast --prompt "Reply with one word: pong"
./spark-ask-http --dry --model auto --prompt "Fix this test failure: …"
make test-ask-gateway   # required dry checks; live opt-in below
```

`--dry` prints the resolved alias and exits 0 with **no network** and
**no key**.

## Run (optional local gateway)

```bash
make                                    # builds spark + spark-ask-http
export AI_GATEWAY_URL=http://127.0.0.1:4000
export SPARK_GATEWAY_KEY=…              # never commit
./spark --live examples/ask_live.spark
./spark --live examples/ask_live_use_fast.spark
./spark --live examples/ask_live_use_code.spark
./spark --live examples/ask_live_use_best.spark
./spark --live examples/ask_live_use_auto.spark
```

Optional live companion proof (skipped when gateway/key missing):

```bash
SPARK_ASK_GATEWAY_LIVE=1 make test-ask-gateway
```

Asm path: `ask` under `--live` → `asm/ask_ops.s` writes the prompt,
`fork`+`execve` `./spark-ask-http`, reads `/tmp/spark-ask-out.txt`,
binds `->`.

## Public tunnel

Public gateway tunnel probes use a dedicated gateway probe credential only.
Never reuse `cursor-ide`. Never echo the probe credential.

```bash
# Language ops (dry = no network; --live = public curl)
./spark --dry-run examples/ask_probe.spark
./spark --dry-run examples/gateway_probe.spark
./spark --live examples/ask_probe.spark   # public tunnel

# Shell companion / wrap
./spark-ask-probe --dry
./spark-ask-probe --live
bash tools/ask/probe_public.sh
```

HTTP **401** or missing probe credential / PROJECT_ID → **credential unavailable**
(exit **4**) — no invented routing conclusion. Do not ask to mint PAT.

## Offline (default)

```bash
./spark --dry-run examples/hello.spark
make test                               # never calls live gateway
make test-ask-gateway                   # companion --dry only
```
