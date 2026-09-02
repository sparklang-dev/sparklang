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

## Honest gaps

- Dry-run / CI never loads a 27B. Fixtures + stub hidden states only.
- Real attach-to-vLLM / llama.cpp needs those runtimes’ hidden-state
  hooks; HF `generate` path is the first-class local integrate.
- Labeled abstain data is **user-supplied** — we ship a tiny fixture,
  not a production corpus.
- Cloud verify-or-refuse is documented + composable; not a second
  gateway plugin.
