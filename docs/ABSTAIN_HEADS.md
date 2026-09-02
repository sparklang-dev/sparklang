# Abstain / IDK heads (SparkLang)

Decode-layer **select-before-sample** so a local (or orchestrated)
model can emit a configured IDK string and halt instead of inventing.

**Not a Bifrost plugin.** Dry-run first. No fake trained weights in
fixtures. No owner/TLP PII on public surfaces.

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
   verify-or-refuse in the orchestrator (SoT / expect / HTTP), not an
   attached head.
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
program.

## Commands (companion)

```bash
# Dry (CI — no GPU weights)
./spark-abstain --dry --stmt-file /tmp/head.stmt --out /tmp/out.json
./spark --dry-run examples/head_abstain.spark

# Train head (CPU; real tiny torch weights when dataset given)
./spark-abstain --live train \
  --dataset examples/fixtures/abstain/labels.jsonl \
  --kind internal --out out/heads/abstain.pt --hidden-dim 64

# Attach to local model directory
./spark-abstain --live attach \
  --model /path/to/hf-model \
  --weights out/heads/abstain.pt \
  --out /path/to/hf-model/spark_abstain_manifest.json

# Gate unit check (Python)
python3 -m sparklang.abstain.gate --p 0.8 --threshold 0.7
```

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
3. Best-effort vLLM: `SPARK_ABSTAIN_VLLM_URL` → POST
   `{url}/spark_hidden` with `{"prompt":…}` → `{"hidden":[…]}`

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

Head `hidden_dim` must match the backbone’s last-layer width
(e.g. train on exported hiddens from that model, not the 64-d
fixture hash vectors).

```bash
pip install -e 'python/[hf]'   # optional: transformers

./spark-abstain --live train \
  --dataset path/to/labels-with-real-hiddens.jsonl \
  --out out/heads/abstain.pt

./spark-abstain --live attach \
  --model /path/to/local-hf-model \
  --weights out/heads/abstain.pt \
  --out /path/to/local-hf-model/spark_abstain_manifest.json

# SELECT-before-SAMPLE in one HF load (prefill → gate → generate)
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

### Env reference

| Env | Role |
|-----|------|
| `SPARK_ABSTAIN_STUB=1` | Fixture gate only (dry heuristics) |
| `SPARK_ABSTAIN_WEIGHTS` | Path to `abstain_head.pt` |
| `SPARK_ABSTAIN_MANIFEST` | Attach manifest JSON |
| `SPARK_ABSTAIN_MODEL` | Local HF dir or hub id |
| `SPARK_ABSTAIN_HF=1` | Allow hub id + HF forward / generate |
| `SPARK_ABSTAIN_HIDDEN` | Pre-exported last-token hidden |
| `SPARK_ABSTAIN_VLLM_URL` | Optional `/spark_hidden` sidecar |

Optional Python extra: `pip install -e 'python/[hf]'`
(`transformers`). CI does **not** install it; unit tests mock
HF tensors.

## Honest gaps

- Dry-run / CI never loads a 27B. Fixtures + stub / synthetic
  hidden only. Live HF is opt-in via env + local weights.
- Head trained on fixture hash features (dim 64) is **not**
  compatible with a real LM hidden size — retrain on exported
  hiddens from the target backbone before claiming gate quality.
- vLLM path needs a host that implements `/spark_hidden`; stock
  OpenAI-compat servers do not export last-layer states.
- llama.cpp / GGUF hidden hooks are still out of scope.
- Labeled abstain data is **user-supplied** — we ship a tiny
  fixture, not a production corpus.
- Cloud verify-or-refuse is documented + composable; not a second
  gateway plugin.
- Do **not** call this production-ready without real head weights
  matched to the live backbone.
- Never resolve `auto`/`code`/`fast` (or similar) as the live model.
