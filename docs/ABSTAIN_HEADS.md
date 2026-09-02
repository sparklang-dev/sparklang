# Abstain / IDK heads — fully effective runbook

Decode-layer **select-before-sample** so a local (or orchestrated)
model can emit a configured IDK string and **HALT** instead of
inventing. This doc is the single “fully effective” path: lowest
ops (decode + real hiddens) through highest (`.spark`, outer
verify-or-refuse, quality stamps).

**Not a Bifrost plugin.** Dry-run first. No fake trained weights in
fixtures. No owner/TLP PII on public surfaces. Live model is an
**explicit** HF path or `org/name` — never gateway aliases
(`auto` / `code` / `fast`).

---

## Architecture (prose)

```
                    ┌─────────────────────────────┐
 Prompt ──────────► │ Outer verify-or-refuse      │
                    │ (SoT / HTTP / expect first)  │
                    └────────────┬────────────────┘
                                 │ inventable + no SoT → IDK + HALT
                                 ▼
                    ┌─────────────────────────────┐
 last hidden h_t ──►│ Abstain head  p(abstain|h)  │
 (HF / file /       │ + optional entropy / margin │
  /spark_hidden)    └────────────┬────────────────┘
                                 │
              SELECT: if p ≥ τ (or entropy/margin)
                                 │
                    yes ──► emit IDK + HALT (no SAMPLE)
                    no  ──► SAMPLE (HF generate or
                            SPARK_ABSTAIN_SAMPLE_URL)
```

Layers:

1. **Lowest — decode machine:** shared `select_before_sample`
   (`gate.py`) used by CLI + runtime. Live ask loads head, scores
   last-token hidden, gates, then samples only on continue.
2. **Lowest — backbone hiddens:** HF prefill, file override, or
   `/spark_hidden` sidecar. Head `hidden_dim` must match.
3. **Highest — language:** `.spark` `head abstain|train|attach|ask`
   via assembler → `./spark-abstain`. Inventable facts use SoT +
   `expect` **before** free generate.
4. **Cloud:** no local hiddens → outer orchestrator only (same
   SoT / expect / HTTP pattern). Not a gateway plugin.

---

## Research (short)

| Approach | Idea | Fit for Spark |
|----------|------|---------------|
| Selective prediction / learned abstention | Extra head `p(abstain\|h)` on last hidden; reject when ≥ τ | **Default** |
| IDK / HAL control token | Train special token; gate on that logit | Optional later |
| Logit entropy / margin heuristics | No train; proxy uncertainty | Secondary (shared gate) |
| Outer verify-or-refuse | SoT / expect / HTTP before generate | **Required** for prices/IDs |
| Full LoRA / PEFT of backbone | Shifts whole distribution | Avoid by default |

---

## Language surface (highest)

```spark
head abstain internal model "fixtures/tiny-lm" \
  weights "out/heads/abstain.pt" threshold 0.7 \
  idk "I don't know." -> gate

head train dataset "examples/fixtures/abstain/corpus_seed.jsonl" \
  kind internal out "out/heads/abstain.pt" hidden_dim 64 -> job

head attach model "path/or/hf-id" \
  weights "out/heads/abstain.pt" \
  out "out/heads/manifest.json" -> attach

head ask "Who is the mayor of Springfield?" -> answer
```

Inventable outer playbook (SoT before ask):

```bash
./spark --dry-run examples/head_ask_inventable_verify.spark
```

See that file: HTTP fixture SoT → `expect` → gated ask refuses
inventing a live dryer price without evidence.

Gate params: `threshold` (τ), optional `entropy` / `margin`
(`SPARK_ABSTAIN_ENTROPY_MAX` / `SPARK_ABSTAIN_MARGIN_MIN`).
On abstain: emit `idk`, `halted=true`, **do not** sample further
inventable tokens.

---

## Dry-run vs live

| Mode | What runs | Weights / hidden |
|------|-----------|------------------|
| `./spark --dry-run` / `./spark-abstain --dry` | Fixture JSON only | No real `.pt`; no HF |
| `SPARK_ABSTAIN_STUB=1` + `--live ask` | Dry inventable heuristics | **Not** real `p(abstain\|h)` |
| `./spark-abstain --live train\|export\|attach` | CPU torch / files | Real `.pt` / JSONL |
| `./spark-abstain --live ask` (no stub) | SELECT-before-SAMPLE | Needs weights + hidden source |
| `--outer-verify` / `SPARK_ABSTAIN_OUTER_VERIFY=1` | Inventable refuse without SoT | No head required when refuse fires |

Dry never invents trained weights. Live refuse gateway short names.

---

## Commands that work today

```bash
# CI / offline (no GPU)
make test-abstain
./spark --dry-run examples/head_abstain.spark
./spark --dry-run examples/head_ask.spark
./spark --dry-run examples/head_ask_inventable_verify.spark

# Shared gate (threshold / entropy / margin)
./spark-abstain --dry gate --p 0.8 --threshold 0.7
./spark-abstain --dry gate --p 0.1 --threshold 0.99 \
  --entropy 3 --entropy-max 1.5
./spark-abstain --dry outer-verify \
  --prompt "What is the dryer start price at that store right now?"

# Corpus
./spark-abstain --live validate-corpus \
  --dataset examples/fixtures/abstain/corpus_seed.jsonl

# Export → train → attach → ask (toy / synthetic / HF)
./spark-abstain --live export \
  --dataset examples/fixtures/abstain/corpus_seed.jsonl \
  --source synthetic --hidden-dim 768 \
  --out out/heads/synth768.jsonl
./spark-abstain --live train \
  --dataset out/heads/synth768.jsonl \
  --out out/heads/abstain768.pt --hidden-dim 768
```

Shipped fixtures:

- `examples/fixtures/abstain/corpus_seed.jsonl` — curated seed
  (~95 honest answer/abstain rows)
- `labels*.jsonl` — legacy CI shapes (bag-hash 64 / toy 16)
- `sot_dryer_price.json` — dry SoT for inventable playbook

---

## Lowest — decode machine

`python/sparklang/abstain/gate.py` → `select_before_sample` is the
**one** gate used by CLI (`spark-abstain gate`) and runtime
(`live_ask` / `try_hf_select_then_sample` / `gated_from_hidden`).

Live generate path:

1. Resolve head + `GateConfig` (weights or manifest).
2. Optional outer inventable refuse.
3. Hidden source priority:
   1. `SPARK_ABSTAIN_HIDDEN` (file)
   2. HF prefill (`SPARK_ABSTAIN_MODEL` + local dir or `SPARK_ABSTAIN_HF=1`)
   3. `SPARK_ABSTAIN_VLLM_URL` → POST `/spark_hidden`
4. Dim mismatch → **halt** with `reason=hidden_dim_mismatch` (no invent).
5. If gate fires → configured IDK + `halted=true` (HF path never
   calls `generate`).
6. Else SAMPLE: in-process HF `generate`, or
   `SPARK_ABSTAIN_SAMPLE_URL` OpenAI-compat, else deferred note.

---

## Lowest — real backbone weights

Owner machines often have large causal LMs (multi‑GB) and incomplete hub
stubs. Prefer an **explicit local dir**.

### One-command tiny model (owner only; CI OFF)

```bash
SPARK_ABSTAIN_ALLOW_TINY_DOWNLOAD=1 \
  ./tools/spark-abstain/tiny_hf_download.sh
# prints: export SPARK_ABSTAIN_MODEL=…
# then:
SPARK_ABSTAIN_HF=1 SPARK_ABSTAIN_MODEL=… \
  make smoke-abstain-hf
```

Default refuses without `SPARK_ABSTAIN_ALLOW_TINY_DOWNLOAD=1`.
CI must leave that unset.

### Existing local HF

```bash
SPARK_ABSTAIN_HF=1 SPARK_ABSTAIN_HF_LOCAL_ONLY=1 \
SPARK_ABSTAIN_MODEL=/path/to/local-hf-model \
  ./tools/spark-abstain/hf_export_train_smoke.sh
```

On success the smoke stamps **`hf_backbone_trained`** via
`mark-quality` (pipeline proven on that host — **still not**
held-out accuracy / production LoRA).

---

## Quality stamps

| Stamp | Meaning |
|-------|---------|
| `fixture_seed` | Text labels only |
| `bag_hash_fixture` | Legacy hash features (dim 64) |
| `toy_backbone` | Seeded toy vectors |
| `synthetic_backbone_dim_match` | Wide synthetic — dim contract only |
| `hf_exported_unverified` | Real HF hiddens exported/trained — no smoke stamp yet |
| `hf_backbone_trained` | export→train→ask smoke succeeded on that backbone |

Never claim “we trained on Llama-70B” from fixtures or smoke.

---

## `/spark_hidden` + SAMPLE URL

Stock OpenAI-compat chat does **not** return last-layer states.
Use the HF sidecar (`tools/spark-abstain/spark_hidden_sidecar.py`)
or the toy stub for CI.

After SELECT continue without in-process HF:

```bash
export SPARK_ABSTAIN_SAMPLE_URL=http://127.0.0.1:8000
# optional SPARK_ABSTAIN_SAMPLE_TOKEN
```

---

## Env reference

| Env | Role |
|-----|------|
| `SPARK_ABSTAIN_STUB=1` | Fixture gate only |
| `SPARK_ABSTAIN_WEIGHTS` / `MANIFEST` | Head files |
| `SPARK_ABSTAIN_MODEL` | Explicit HF dir / hub id |
| `SPARK_ABSTAIN_HF=1` | Allow hub + HF forward |
| `SPARK_ABSTAIN_HF_LOCAL_ONLY=1` | No hub download |
| `SPARK_ABSTAIN_HIDDEN` | File hidden override |
| `SPARK_ABSTAIN_VLLM_URL` | `/spark_hidden` base |
| `SPARK_ABSTAIN_SAMPLE_URL` | OpenAI-compat SAMPLE after continue |
| `SPARK_ABSTAIN_ENTROPY_MAX` / `MARGIN_MIN` | Shared secondary trips |
| `SPARK_ABSTAIN_OUTER_VERIFY=1` | Inventable outer refuse |
| `SPARK_ABSTAIN_SOT_OK=1` | SoT already verified |
| `SPARK_ABSTAIN_ALLOW_TINY_DOWNLOAD=1` | Owner tiny HF download (CI OFF) |

Extras: `pip install -e 'python/[hf]'` · `python/[sidecar]`.

---

## Discovery

- README table → this doc
- `docs/LANGUAGE.md` → `head abstain` / train / attach / ask
- `make test-abstain` · `make smoke-abstain-hf`

---

## Known limits (sharp)

- CI never loads a multi‑GB LM; fixtures + toy/synthetic/stub only.
- File / sidecar continue without `SAMPLE_URL` or HF → SAMPLE
  deferred (honest empty `text` + note).
- Stock vLLM lacks native hidden export — use sidecar.
- llama.cpp / GGUF hidden hooks out of scope.
- Corpus is curated seed (~95), not a production billion.
- Cloud verify-or-refuse is orchestrator composition — not Bifrost.
- `hf_backbone_trained` ≠ published accuracy claim.
