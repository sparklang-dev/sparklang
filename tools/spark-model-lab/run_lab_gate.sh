#!/usr/bin/env bash
# Offline gate for model lab (reverse / compile / modify).
set -euo pipefail
cd "$(dirname "$0")/../.."

./spark --dry-run examples/model_lab.spark >/tmp/spark-model-lab.txt
grep -q '"op":"reverse"' /tmp/spark-model-lab.txt
grep -q Qwen3ForCausalLM /tmp/spark-model-lab.txt
grep -q '"op":"compile"' /tmp/spark-model-lab.txt
grep -q sparkbc /tmp/spark-model-lab.txt
grep -q '"op":"modify"' /tmp/spark-model-lab.txt
grep -q keep_existing /tmp/spark-model-lab.txt
grep -q keep_special_training /tmp/spark-model-lab.txt
grep -q '"op":"train"' /tmp/spark-model-lab.txt
grep -q head_abstain /tmp/spark-model-lab.txt
grep -q "I don't know." /tmp/spark-model-lab.txt
test -f out/lab/model_lab.sparkbc
test -f out/lab/MODIFY

./spark-model-lab --dry reverse \
  >/tmp/spark-model-lab-cli.txt
grep -q '"op": "reverse"\|"op":"reverse"' /tmp/spark-model-lab-cli.txt
grep -q keep_special_training /tmp/spark-model-lab-cli.txt

./spark-model-lab --live reverse \
  --model examples/fixtures/models/tiny-lm \
  >/tmp/spark-model-lab-live.txt
grep -q '"mode": "live"\|"mode":"live"' /tmp/spark-model-lab-live.txt
grep -q Qwen3ForCausalLM /tmp/spark-model-lab-live.txt
grep -q hidden_size /tmp/spark-model-lab-live.txt

PYTHONPATH=python python3 tools/spark-model-lab/test_reverse.py

echo "test-model-lab OK"
