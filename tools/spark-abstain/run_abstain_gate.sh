#!/usr/bin/env bash
# Offline gate for abstain heads (no GPU / no network invent).
set -euo pipefail
cd "$(dirname "$0")/../.."

printf '%s\n' \
  'head abstain internal model "fixture-model" weights "out/heads/abstain.pt" threshold 0.7 idk "I don'\''t know." -> gate' \
  > /tmp/spark-ab-stmt.txt
./spark-abstain --dry --stmt-file /tmp/spark-ab-stmt.txt \
  --out /tmp/spark-ab-out.json >/tmp/spark-ab-stdout.txt
grep -q head_abstain /tmp/spark-ab-out.json
grep -q '"op":"head_abstain"' /tmp/spark-ab-out.json

./spark-abstain --dry gate --p 0.9 --threshold 0.7 \
  >/tmp/spark-ab-gate1.txt
grep -q '"abstain":true' /tmp/spark-ab-gate1.txt
./spark-abstain --dry gate --p 0.2 --threshold 0.7 \
  >/tmp/spark-ab-gate2.txt
grep -q '"abstain":false' /tmp/spark-ab-gate2.txt

PYTHONPATH=python python3 tools/spark-abstain/test_abstain.py

./spark --dry-run examples/head_abstain.spark \
  >/tmp/spark-ab-ex1.txt
grep -q head_abstain /tmp/spark-ab-ex1.txt
./spark --dry-run examples/head_ask.spark >/tmp/spark-ab-ex2.txt
grep -q '"abstain":true' /tmp/spark-ab-ex2.txt
./spark --dry-run examples/head_train.spark \
  >/tmp/spark-ab-ex3.txt
grep -q head_train /tmp/spark-ab-ex3.txt

# Live CPU train on fixture (real .pt, not a marker stub)
rm -rf out/heads-test
mkdir -p out/heads-test
./spark-abstain --live train \
  --dataset examples/fixtures/abstain/labels.jsonl \
  --kind internal \
  --out out/heads-test/abstain.pt \
  --hidden-dim 64 >/tmp/spark-ab-train.txt
grep -q '"state":"succeeded"' /tmp/spark-ab-train.txt
test -f out/heads-test/abstain.pt
test -f out/heads-test/abstain.meta.json

./spark-abstain --live attach \
  --model out/heads-test \
  --weights out/heads-test/abstain.pt \
  --out out/heads-test/manifest.json >/tmp/spark-ab-att.txt
grep -q head_attach /tmp/spark-ab-att.txt
test -f out/heads-test/manifest.json
test -f out/heads-test/spark_abstain_manifest.json

# Live ask with synthetic hidden file (no HF download)
PYTHONPATH=python python3 - <<'PY'
import torch
from pathlib import Path
p = Path("out/heads-test/hidden.pt")
# 64-d vector matching fixture-trained head
torch.save(torch.zeros(64), p)
print(p)
PY
./spark-abstain --live ask \
  --prompt "What is gravity?" \
  --weights out/heads-test/abstain.pt \
  --hidden out/heads-test/hidden.pt \
  >/tmp/spark-ab-ask-live.txt
grep -q '"op":"head_ask"' /tmp/spark-ab-ask-live.txt
grep -q '"mode":"live"' /tmp/spark-ab-ask-live.txt
grep -q '"hidden_source":"file"' /tmp/spark-ab-ask-live.txt

# Stub ask still works without weights
SPARK_ABSTAIN_STUB=1 ./spark-abstain --live ask \
  --prompt "Who is the mayor of Springfield?" \
  >/tmp/spark-ab-ask-stub.txt
grep -q '"abstain":true' /tmp/spark-ab-ask-stub.txt

echo "test-abstain OK"
