# spark-abstain companion

Forked by GAS `head …` statements. Dry fixtures by default.
Live: CPU export / train / attach / gated ask (not LoRA).

See [docs/ABSTAIN_HEADS.md](../../docs/ABSTAIN_HEADS.md).

```bash
./spark-abstain --dry --stmt-file stmt.txt --out out.json

# Prefer: curated corpus → synthetic (or HF) export → train
./spark-abstain --live validate-corpus \
  --dataset examples/fixtures/abstain/corpus_seed.jsonl
./spark-abstain --live export \
  --dataset examples/fixtures/abstain/corpus_seed.jsonl \
  --source synthetic --hidden-dim 768 \
  --out out/heads/synth768.jsonl
./spark-abstain --live train \
  --dataset out/heads/synth768.jsonl \
  --out out/heads/abstain768.pt --hidden-dim 768

# Flagship: SoT + abstain head + inventable/open ask (no invent)
./spark --dry-run examples/no_invent.spark

# Outer inventable verify (no weights when refuse fires)
./spark-abstain --dry outer-verify \
  --prompt "What is the dryer start price at that store right now?"
./spark --dry-run examples/head_ask_inventable_verify.spark

# Toy dim-16 (CI contract)
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

# Live ask: outer verify-or-refuse is ON by default (IDK without SoT)
./spark-abstain --live ask \
  --prompt "What is gravity?" \
  --weights out/heads/abstain.pt \
  --hidden /tmp/hidden.pt
# Inventable → IDK unless --sot-ok (or SPARK_ASK_SOT_OK=1)
./spark-abstain --live ask \
  --prompt "Who is the mayor of Springfield?"
SPARK_ABSTAIN_STUB=1 ./spark-abstain --live ask \
  --prompt "Who is the mayor of Springfield?"

# Optional HF export→train→ask (skips unless env+local model)
# SPARK_ABSTAIN_HF=1 SPARK_ABSTAIN_MODEL=/path/to/hf \
#   ./tools/spark-abstain/hf_export_train_smoke.sh
# Owner tiny download (CI OFF):
# SPARK_ABSTAIN_ALLOW_TINY_DOWNLOAD=1 \
#   ./tools/spark-abstain/tiny_hf_download.sh

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
Full runbook: [docs/ABSTAIN_HEADS.md](../../docs/ABSTAIN_HEADS.md).
