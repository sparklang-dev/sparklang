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
| `SPARK_MODEL` | Optional fallback when `--model` omitted |

Pass an **explicit** model id (HF id / path / configured gateway model
string). `--model auto` is **rejected** — Spark does not pick Bifrost-style
aliases from task text.

Never route Spark compute to voice / `:8010` / reserved voice GPU.

## Offline dry gate (CI / no key)

```bash
make spark-ask-http
./spark-ask-http --dry --model fixtures/tiny-lm --prompt "Reply with one word: pong"
make test-ask-gateway   # required dry checks; live opt-in below
```

`--dry` prints the model line and exits 0 with **no network** and
**no key**.

## Run (optional local gateway)

```bash
make                                    # builds spark + spark-ask-http
export AI_GATEWAY_URL=http://127.0.0.1:4000
export SPARK_GATEWAY_KEY=…              # never commit
./spark --live examples/ask_live.spark
./spark --live examples/ask_live_explicit.spark
```

Optional live companion proof (skipped when gateway/key missing):

```bash
SPARK_ASK_GATEWAY_LIVE=1 make test-ask-gateway
```

Asm path: `ask` under `--live` → `asm/ask_ops.s` writes the prompt,
`fork`+`execve` `./spark-ask-http`, reads `/tmp/spark-ask-out.txt`,
binds `->`.

## Streaming (`--stream` / `ask stream`)

Token/SSE path is **shipped** on the companion:

```bash
./spark-ask-http --dry --stream --model fixtures/tiny-lm --prompt "ping"
# → dry … stream=1 … dry ok (no network)

./spark-ask-http --stream --model fast --prompt "Say hi" \
  --out /tmp/spark-ask-out.txt
```

Live request sets `"stream":true` (+ `stream_options.include_usage`
when the gateway supports it). Deltas print to stdout as they arrive;
`--out` gets the accumulated text. Language form under `--live`:

```
ask stream "Say hello in three words" -> reply
```

`asm/ask_ops.s` detects `stream "` on the line and passes `--stream`.
Dry-run of a `.spark` file still uses the offline ask fixtures (no
network); use companion `--dry --stream` for the offline stream gate.

Example: `examples/ask_stream.spark`. Gate: `make test-ask-gateway`
(`PASS dry_stream`).

## Accounting (wall-clock + usage)

Live `./spark-ask-http` prints a real wall-clock line (never invents
tokens):

```
[accounting] latency_ms=87 prompt_tokens=12 completion_tokens=9 total_tokens=21
```

`latency_ms` is `CLOCK_MONOTONIC` around the HTTP/SSE round-trip.
`prompt_tokens` / `completion_tokens` / `total_tokens` come from the
gateway `usage` object when present — otherwise they stay 0 and a
`note=no usage field` line is printed.

Each live ask appends one JSONL row to
`SPARK_ACCOUNT_FILE` (default `/tmp/spark-ask-account.jsonl`).
`./spark --live` truncates that file at start and prints a run rollup
at end:

```
[accounting-run] asks=2 latency_ms=140 prompt_tokens=20 completion_tokens=18 total_tokens=38
```

Offline proof (no gateway):

```bash
./spark-ask-http --rollup --account-file fixtures.jsonl
make test-ask-gateway   # includes PASS rollup
```

Dry-run still prints zeros (`note=dry-run`) and does not append.

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
