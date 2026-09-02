# spark-abstain companion

Forked by GAS `head …` statements. Dry fixtures by default.
Live: CPU train / attach of a real abstain head (not LoRA).

See [docs/ABSTAIN_HEADS.md](../../docs/ABSTAIN_HEADS.md).

```bash
./spark-abstain --dry --stmt-file stmt.txt --out out.json
./spark-abstain --live train \
  --dataset examples/fixtures/abstain/labels.jsonl \
  --out out/heads/abstain.pt --hidden-dim 64
./spark-abstain --live attach \
  --model /path/to/hf-model \
  --weights out/heads/abstain.pt \
  --out /path/to/hf-model/spark_abstain_manifest.json
make test-abstain
```
