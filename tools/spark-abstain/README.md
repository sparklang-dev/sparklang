# spark-abstain companion

Forked by GAS `head …` statements. Dry fixtures by default.
Live: CPU export / train / attach / gated ask (not LoRA).

See [docs/ABSTAIN_HEADS.md](../../docs/ABSTAIN_HEADS.md).

```bash
./spark-abstain --dry --stmt-file stmt.txt --out out.json

# Prefer: export dim-matched hiddens, then train
./spark-abstain --live export \
  --dataset examples/fixtures/abstain/labels_text.jsonl \
  --out out/heads/exported.jsonl --hidden-dim 16
./spark-abstain --live train \
  --dataset out/heads/exported.jsonl \
  --out out/heads/abstain.pt --hidden-dim 16

# Legacy bag-hash fixture (dim 64)
./spark-abstain --live train \
  --dataset examples/fixtures/abstain/labels.jsonl \
  --out out/heads/abstain64.pt --hidden-dim 64

./spark-abstain --live attach \
  --model /path/to/hf-model \
  --weights out/heads/abstain.pt \
  --out /path/to/hf-model/spark_abstain_manifest.json

# Live ask: synthetic hidden (CI) or HF when SPARK_ABSTAIN_HF=1
./spark-abstain --live ask \
  --prompt "What is gravity?" \
  --weights out/heads/abstain.pt \
  --hidden /tmp/hidden.pt
SPARK_ABSTAIN_STUB=1 ./spark-abstain --live ask \
  --prompt "Who is the mayor of Springfield?"

# HF /spark_hidden sidecar (beside stock vLLM chat)
pip install -e 'python/[sidecar]'
PYTHONPATH=python python3 tools/spark-abstain/spark_hidden_sidecar.py \
  --model /path/to/hf-model --port 8765
SPARK_ABSTAIN_VLLM_URL=http://127.0.0.1:8765 \
  ./spark-abstain --live ask --prompt "…" --weights out/heads/abstain.pt

# CI contract stub (toy vectors)
PYTHONPATH=python python3 tools/spark-abstain/spark_hidden_stub.py \
  --port 8765 --dim 16

make test-abstain
```

Contract + client: `python/sparklang/abstain/spark_hidden.py`.
