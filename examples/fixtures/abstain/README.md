# Abstain labeled corpus (fixtures)

Curated **seed** JSONL for SparkLang abstain heads (~105 rows).
Not a production accuracy dataset. Do not invent a fake large
corpus or claim Llama-70B / live LM gate quality from these rows.

## Files

| File | Role |
|------|------|
| `corpus_seed.jsonl` | Curated text + `label` 0/1 + `reason` (preferred; dozens of rows) |
| `sot_dryer_price.json` | Dry SoT fixture for inventable outer verify playbook |
| `labels_text.jsonl` | Minimal text+label (legacy / CI export input) |
| `labels.jsonl` | Legacy bag-hash dim **64** features |
| `labels_exported.jsonl` | Toy-backbone dim **16** export→train contract |

## Row schema

Required:

- `text` (or `prompt`) — prompt string
- `label` — `0` = **answer** (SAMPLE OK), `1` = **abstain** (prefer IDK)

Optional:

- `label_name` — `"answer"` / `"abstain"` (derived if omitted)
- `reason` — why this row is answer vs abstain (human note)
- `id`, `tags` — stable id / free tags
- `hidden`, `dim`, `source` — after `spark-abstain --live export`

`source` honesty:

- `text` — labels only
- `toy` — CI toy backbone (default dim 16)
- `synthetic_backbone` — dim-matched synthetic vectors (e.g. 768);
  proves wide-head train/ask, **not** HF prefill
- `hf` / `hf_prefill` — exported from an explicit HF model
- `bag_hash` — legacy text→hash features (dim 64)

## Grow the corpus

1. Add rows to a private or repo JSONL (no PII, no owner secrets).
2. Validate: `./spark-abstain --live validate-corpus --dataset PATH`
3. Export hiddens from the **target** backbone:
   ```bash
   SPARK_ABSTAIN_HF=1 SPARK_ABSTAIN_HF_LOCAL_ONLY=1 \
   ./spark-abstain --live export \
     --dataset examples/fixtures/abstain/corpus_seed.jsonl \
     --model /path/to/local-hf-model \
     --out out/heads/from-hf.jsonl
   ```
4. Train: `./spark-abstain --live train --dataset out/heads/from-hf.jsonl --out out/heads/abstain.pt`
5. Attach + ask with the **same** backbone `hidden_dim`.

Offline dim-match smoke (no HF):

```bash
./spark-abstain --live export \
  --dataset examples/fixtures/abstain/corpus_seed.jsonl \
  --source synthetic --hidden-dim 768 \
  --out out/heads/synth768.jsonl
./spark-abstain --live train \
  --dataset out/heads/synth768.jsonl \
  --out out/heads/abstain768.pt --hidden-dim 768

# Honest held-out metrics (retrain on train fold)
./spark-abstain --live eval \
  --dataset out/heads/synth768.jsonl \
  --train-out out/heads/abstain768-heldout.pt \
  --holdout 0.2 --out out/heads/eval768.json
```

Quality stamps in export/train JSON (`toy_backbone`,
`synthetic_backbone_dim_match`, `hf_exported_unverified`,
`hf_backbone_trained`, `bag_hash_fixture`,
`heldout_eval_retrained`) mean **fixture / pipeline** — never
production accuracy. Use
`./spark-abstain --live mark-quality --weights …` only after a
real HF export→train→ask smoke on that backbone.
