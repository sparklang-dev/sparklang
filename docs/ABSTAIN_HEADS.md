# Abstain / IDK heads (SparkLang)

Decode-layer **select-before-sample** so a local (or orchestrated)
model can emit a configured IDK string and halt instead of inventing.

**Not a Bifrost plugin.** Dry-run first. No fake trained weights in
fixtures. No owner/TLP PII on public surfaces. Live model is an
**explicit** HF path or `org/name` — never gateway aliases
(`auto` / `code` / `fast`).

## Research (short)

| Approach | Idea | Fit for Spark |
|----------|------|---------------|
| Selective prediction / learned abstention | Extra head `p(abstain\|h)` on last hidden; reject when ≥ τ | **Default** |
| IDK / HAL control token | Train special token; gate on that logit | Optional later |
| Logit entropy / margin heuristics | No train; proxy uncertainty | Useful secondary signal |
| Speculative-decode gates | Accept/reject draft tokens | Different problem |
| Full LoRA / PEFT of backbone | Shifts whole distribution | Avoid for *train job* methods; optional only if user opts in |
| Outer verify-or-refuse | Cloud: ask → check SoT → refuse | Cloud default |

**Verdict — default Spark architecture**

1. **Internal head:** small linear (or 1-hidden MLP) on the frozen
   backbone’s last-token hidden state → abstain logit. Saved as
   `abstain_head.pt` + `manifest.json` beside the model; loaded at
   generate time. Backbone stays frozen (classic last-layer probe).
2. **External head:** same architecture as a **sidecar** scorer. Takes
   exported hidden vectors (or top-k logprobs) from a local generate
   step; does not mutate the HF module graph.
3. **Cloud models:** no local hidden states → **outer**
   verify-or-refuse in the **orchestrator** (SoT / `expect` / HTTP),
   not an attached head and **not** Bifrost alias picking.
4. **Why not LoRA by default:** Spark’s CPU train methods already
   reject LoRA for job methods; abstain only needs a binary gate.
   A probe is cheaper, CPU-trainable, and attachable to an existing
   local HF / vLLM-exported checkpoint without claiming a full fine-tune.

Citations (techniques, not code deps): selective classification
(Geifman & El-Yaniv), learned abstention / reject options, HAL/IDK
tokens in dialogue models, PEFT last-layer probes.

## Language surface

```spark
# Declare / attach a gate (dry = fixtures; live = real head files)
head abstain internal model "fixtures/tiny-lm" \
  weights "out/heads/abstain.pt" threshold 0.7 \
  idk "I don't know." -> gate

head abstain external model "fixtures/tiny-lm" \
  weights "out/heads/abstain_ext.pt" threshold 0.7 -> gate

# Train a head on labeled abstain JSONL (CPU; frozen features)
head train dataset "examples/fixtures/abstain/labels.jsonl" \
  kind internal out "out/heads/abstain.pt" hidden_dim 64 -> job

# Attach head weights to a local model dir (manifest only + copy)
head attach model "path/or/hf-id" \
  weights "out/heads/abstain.pt" \
  out "out/heads/manifest.json" -> attach

# Gated ask: SELECT before SAMPLE (dry stub or local generate)
head ask "Who is the mayor of Springfield?" -> answer
```

Gate params: `threshold` (τ), optional `entropy` / `margin` floors.
On abstain: emit `idk` string, set `halted=true`, do **not** sample
continuation tokens.

## Dry-run vs live

| Mode | What runs | Weights / hidden |
|------|-----------|------------------|
| `./spark --dry-run` / `./spark-abstain --dry` | Fixture JSON only | No real `.pt`; no HF |
| `SPARK_ABSTAIN_STUB=1` + `--live ask` | Dry inventable heuristics | **Not** real `p(abstain\|h)` |
| `./spark-abstain --live train\|export\|attach` | CPU torch / files | Real `.pt` / JSONL |
| `./spark-abstain --live ask` (no stub) | SELECT-before-SAMPLE | Needs weights + hidden source |

Dry never invents trained weights. Live refuse gateway short names.

## Runtime flow

```
hidden h_t  →  head  →  p_abstain
                │
        SELECT: if p ≥ τ (or entropy/margin trip)
                │ yes → emit IDK + HALT
                │ no  → SAMPLE next token as usual
```

Optional SoT / logit mask for inventable facts stays orthogonal
(`expect`, HTTP verify, retrieve) — compose in the same `.spark`
program. Cloud outer verify-or-refuse is that orchestrator path.

## Commands (`./spark-abstain`)

```bash
# Dry (CI — no GPU weights)
./spark-abstain --dry --stmt-file /tmp/head.stmt --out /tmp/out.json
./spark --dry-run examples/head_abstain.spark

# Export dim-matched hiddens (toy = CI; --model = real HF)
./spark-abstain --live export \
  --dataset examples/fixtures/abstain/labels_text.jsonl \
  --out out/heads/exported.jsonl --hidden-dim 16

# Train head on exported (or bag-hash) JSONL
./spark-abstain --live train \
  --dataset examples/fixtures/abstain/labels_exported.jsonl \
  --kind internal --out out/heads/abstain.pt --hidden-dim 16

# Attach to local model directory
./spark-abstain --live attach \
  --model /path/to/hf-model \
  --weights out/heads/abstain.pt \
  --out /path/to/hf-model/spark_abstain_manifest.json

# Gate unit check (Python)
python3 -m sparklang.abstain.gate --p 0.8 --threshold 0.7

make test-abstain
```

Shipped fixtures:

- `examples/fixtures/abstain/corpus_seed.jsonl` — curated seed
  (text + `label` 0/1 + `reason` / tags). Preferred labeled corpus.
- `examples/fixtures/abstain/labels.jsonl` — bag-hash dim **64** (legacy CI)
- `examples/fixtures/abstain/labels_text.jsonl` — text + label only
- `examples/fixtures/abstain/labels_exported.jsonl` — toy-backbone
  dim **16** (export→train contract)
- `examples/fixtures/abstain/README.md` — schema + how to grow

Validate: `./spark-abstain --live validate-corpus --dataset …`

## Train from exported backbone hiddens (preferred)

Head `hidden_dim` **must** equal the backbone last-layer width.
Pipeline:

1. Label prompts (`text` + `label` 0/1) in JSONL — start from
   `corpus_seed.jsonl`.
2. **Export** last-token hiddens at that width.
3. **Train** the probe on those rows.
4. **Attach** + **ask** with the same backbone (or matching
   `--hidden` / `/spark_hidden`).

```bash
# A) Real HF backbone (needs pip install -e 'python/[hf]' + weights)
SPARK_ABSTAIN_HF=1 SPARK_ABSTAIN_HF_LOCAL_ONLY=1 \
./spark-abstain --live export \
  --dataset examples/fixtures/abstain/corpus_seed.jsonl \
  --model /path/to/local-hf-model \
  --source hf \
  --out out/heads/from-hf.jsonl
# hidden_dim inferred from the model; do not pass a mismatched --hidden-dim

./spark-abstain --live train \
  --dataset out/heads/from-hf.jsonl \
  --out out/heads/abstain.pt

# Optional one-shot smoke (skips if env/model missing):
#   SPARK_ABSTAIN_HF=1 SPARK_ABSTAIN_MODEL=/path/to/local-hf-model \
#     ./tools/spark-abstain/hf_export_train_smoke.sh

# B) Synthetic dim-matched (wide CI — not a real LM)
./spark-abstain --live export \
  --dataset examples/fixtures/abstain/corpus_seed.jsonl \
  --source synthetic --hidden-dim 768 \
  --out out/heads/synth768.jsonl
./spark-abstain --live train \
  --dataset out/heads/synth768.jsonl \
  --out out/heads/abstain768.pt --hidden-dim 768

# C) CI / offline — toy backbone (same CLI, honest source=toy)
./spark-abstain --live export \
  --dataset examples/fixtures/abstain/labels_text.jsonl \
  --out out/heads/exported.jsonl --hidden-dim 16
./spark-abstain --live train \
  --dataset out/heads/exported.jsonl \
  --out out/heads/abstain16.pt --hidden-dim 16
```

Quality stamps (`quality` in export/train JSON):

| Stamp | Meaning |
|-------|---------|
| `fixture_seed` | Text labels only |
| `bag_hash_fixture` | Legacy hash features (dim 64) |
| `toy_backbone` | Seeded toy vectors |
| `synthetic_backbone_dim_match` | Wide synthetic — dim contract only |
| `hf_exported_unverified` | Real HF hiddens — still not a published accuracy claim |

Toy / synthetic export is **not** production LoRA and **not** a
27B/70B. HF export is opt-in and still **unverified** until you
evaluate on held-out prompts for **your** backbone.

## Live generate path (HF / hidden file / vLLM)

`head ask` live refuses to invent. It needs a **real**
`p(abstain|h)` from a trained head + a last-token hidden.

**No gateway alias picking.** Live model is an explicit local HF
directory or hub `org/name` only — never `auto` / `code` / `fast`
(or other short gateway names). Dry-run / stub does not invent a
model line from aliases.

**Hidden source priority**

1. `SPARK_ABSTAIN_HIDDEN` — `.pt` tensor or JSON float list
2. HF transformers prefill when model path exists **or**
   `SPARK_ABSTAIN_HF=1` + explicit hub id (`SPARK_ABSTAIN_MODEL`)
3. Best-effort vLLM-shaped sidecar: `SPARK_ABSTAIN_VLLM_URL` → POST
   `{url}/spark_hidden` (see contract below)

**Head weights**

- `SPARK_ABSTAIN_WEIGHTS` — `abstain_head.pt` from `head train`
- or `SPARK_ABSTAIN_MANIFEST` — attach manifest (includes weights,
  threshold, idk, model)

**Stub (CI / no model)**

```bash
SPARK_ABSTAIN_STUB=1 ./spark-abstain --live ask \
  --prompt "Who is the mayor of Springfield?"
```

Uses dry inventable heuristics — **not** a real `p(abstain|h)`.

### Example: local HF dir (no hub download)

```bash
pip install -e 'python/[hf]'   # optional: transformers

SPARK_ABSTAIN_HF=1 \
./spark-abstain --live ask \
  --prompt "Who is the mayor of Springfield?" \
  --model /path/to/local-hf-model \
  --weights out/heads/abstain.pt \
  --manifest /path/to/local-hf-model/spark_abstain_manifest.json
```

Or via env only (GAS `./spark --live examples/head_ask.spark`):

```bash
export SPARK_ABSTAIN_HF=1
export SPARK_ABSTAIN_MODEL=/path/to/local-hf-model
export SPARK_ABSTAIN_WEIGHTS=out/heads/abstain.pt
./spark --live examples/head_ask.spark
```

### Example: pre-exported hidden (offline / CI-shaped)

```bash
# hidden.pt = last-token vector, dim == head.hidden_dim
./spark-abstain --live ask \
  --prompt "What is gravity?" \
  --weights out/heads/abstain.pt \
  --hidden /tmp/hidden.pt
```

Continue without an in-process HF generate returns
`"note": "continue - SAMPLE deferred …"` and empty `text`.

### vLLM `/spark_hidden` contract

Stock OpenAI-compat `/v1/chat/completions` does **not** return
last-layer states. Spark expects an optional sidecar (or vLLM
plugin that speaks the same path):

```http
POST {SPARK_ABSTAIN_VLLM_URL}/spark_hidden
Content-Type: application/json
Authorization: Bearer <optional SPARK_ABSTAIN_VLLM_TOKEN>

{"prompt":"Who is the mayor of Springfield?",
 "max_length": 512, "layer": -1}
```

Optional request fields: `model` (must match loaded backbone or
be omitted), `max_length`, `layer` (default `-1` = last layer).

```json
{"object":"spark.hidden",
 "hidden":[0.1, -0.2],
 "dim": 2,
 "model":"/path/to/hf-model",
 "source":"hf_prefill",
 "layer": -1,
 "prompt_tokens": 8}
```

- `object` — `"spark.hidden"` (OpenAI-adjacent type tag)
- `hidden` — float list, length = head `hidden_dim`
- `dim` — required for hosts that send it; must equal
  `len(hidden)`
- `source` — `hf_prefill` (real sidecar) or `toy_stub` (CI)
- Non-2xx / missing `hidden` / dim mismatch → client returns
  no invent; ask fails closed (or falls through to next source)
- Shared parsers: `python/sparklang/abstain/spark_hidden.py`

Also: `GET /health` → `{"ok":true, "model":"…"}`.

### HF sidecar (production-shaped)

Loads one **explicit** HF dir / hub id and serves last-token
hiddens. Sit beside stock vLLM chat — do not expect stock vLLM
to grow this path without a plugin.

```bash
pip install -e 'python/[sidecar]'   # fastapi + uvicorn + transformers

PYTHONPATH=python python3 \
  tools/spark-abstain/spark_hidden_sidecar.py \
  --model /path/to/hf-model --host 127.0.0.1 --port 8765

# optional auth:
#   --token secret   # or SPARK_HIDDEN_TOKEN / SPARK_ABSTAIN_VLLM_TOKEN

export SPARK_ABSTAIN_VLLM_URL=http://127.0.0.1:8765
# export SPARK_ABSTAIN_VLLM_TOKEN=secret
# export SPARK_ABSTAIN_VLLM_TIMEOUT=60
./spark-abstain --live ask \
  --prompt "Who is the mayor of Springfield?" \
  --weights out/heads/abstain.pt
```

Env for the process: `SPARK_HIDDEN_MODEL` (or
`SPARK_ABSTAIN_MODEL`), `SPARK_HIDDEN_HOST`, `SPARK_HIDDEN_PORT`,
`SPARK_HIDDEN_TOKEN`. Never pass `auto` / `code` / `fast`.

### Laptop stub (CI / toy)

Toy vectors — same JSON contract, **not** a real LM:

```bash
PYTHONPATH=python python3 \
  tools/spark-abstain/spark_hidden_stub.py --port 8765 --dim 16
# then:
# SPARK_ABSTAIN_VLLM_URL=http://127.0.0.1:8765 \
#   ./spark-abstain --live ask … --weights out/heads/abstain16.pt
```

### Env reference

| Env | Role |
|-----|------|
| `SPARK_ABSTAIN_STUB=1` | Fixture gate only (dry heuristics) |
| `SPARK_ABSTAIN_WEIGHTS` | Path to `abstain_head.pt` |
| `SPARK_ABSTAIN_MANIFEST` | Attach manifest JSON |
| `SPARK_ABSTAIN_MODEL` | Local HF dir or hub id |
| `SPARK_ABSTAIN_HF=1` | Allow hub id + HF forward / generate |
| `SPARK_ABSTAIN_HF_LOCAL_ONLY=1` | `local_files_only` — no hub download |
| `TRANSFORMERS_OFFLINE=1` | Same offline preference for HF loads |
| `SPARK_ABSTAIN_HIDDEN` | Pre-exported last-token hidden |
| `SPARK_ABSTAIN_VLLM_URL` | `/spark_hidden` sidecar base URL |
| `SPARK_ABSTAIN_VLLM_TIMEOUT` | Client timeout seconds (default 30) |
| `SPARK_ABSTAIN_VLLM_TOKEN` | Optional Bearer for sidecar |
| `SPARK_HIDDEN_MODEL` | Sidecar loaded backbone (explicit) |
| `SPARK_HIDDEN_HOST` / `PORT` / `TOKEN` | Sidecar listen / auth |

Optional Python extras:

- `pip install -e 'python/[hf]'` — transformers only
- `pip install -e 'python/[sidecar]'` — FastAPI + uvicorn + HF

CI does **not** install them; unit tests mock HTTP / HF tensors.

## Honest gaps

- Dry-run / CI never loads a 27B. Fixtures + stub / synthetic /
  toy hidden only. Live HF is opt-in via env + **local** weights
  (`SPARK_ABSTAIN_HF_LOCAL_ONLY` / `TRANSFORMERS_OFFLINE` preferred).
- Head trained on fixture bag-hash (dim 64), toy export (dim 16),
  or synthetic backbone (e.g. 768) is **not** compatible with a
  real LM hidden size unless that size matches — retrain on
  exported hiddens from the **target** backbone before claiming
  gate quality. Synthetic proves the **dim contract**, not accuracy.
- Stock vLLM still lacks native hidden export; use the HF
  sidecar (or a future in-process plugin speaking
  `/spark_hidden`). The stub is for contract/CI only.
- llama.cpp / GGUF hidden hooks are still out of scope.
- Labeled abstain data starts from a **tiny curated seed**
  (`corpus_seed.jsonl`) — grow it yourself; we do **not** ship a
  production corpus and do **not** invent large fake datasets.
- Cloud verify-or-refuse is documented + composable (orchestrator);
  not a second gateway plugin and not Bifrost aliases.
- Do **not** call this production-ready without real head weights
  matched to the live backbone. Not production LoRA.
- Never resolve `auto`/`code`/`fast` (or similar) as the live model.
- Never claim “we trained on Llama-70B” from fixtures or smoke.