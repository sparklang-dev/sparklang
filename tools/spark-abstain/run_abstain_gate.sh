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

# Inventable outer verify-or-refuse playbook (SoT before ask)
./spark --dry-run examples/head_ask_inventable_verify.spark \
  >/tmp/spark-ab-invent.txt
grep -q '"abstain":true' /tmp/spark-ab-invent.txt
grep -q price_usd /tmp/spark-ab-invent.txt

# Shared gate: entropy / margin trips via CLI
./spark-abstain --dry gate --p 0.1 --threshold 0.99 \
  --entropy 3.0 --entropy-max 1.5 >/tmp/spark-ab-ent.txt
grep -q '"reason":"entropy"' /tmp/spark-ab-ent.txt
./spark-abstain --dry gate --p 0.1 --threshold 0.99 \
  --margin 0.05 --margin-min 0.2 >/tmp/spark-ab-mar.txt
grep -q '"reason":"margin"' /tmp/spark-ab-mar.txt

# Outer-verify helper (no weights)
./spark-abstain --dry outer-verify \
  --prompt "What is the dryer start price at that store right now?" \
  >/tmp/spark-ab-outer.txt
grep -q '"reason":"outer_verify"' /tmp/spark-ab-outer.txt
grep -q '"halted":true' /tmp/spark-ab-outer.txt

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

# Export (toy backbone) → train dim-matched head → ask
./spark-abstain --live export \
  --dataset examples/fixtures/abstain/labels_text.jsonl \
  --out out/heads-test/exported.jsonl \
  --hidden-dim 16 >/tmp/spark-ab-export.txt
grep -q '"source":"toy"' /tmp/spark-ab-export.txt
grep -q '"hidden_dim":16' /tmp/spark-ab-export.txt
./spark-abstain --live train \
  --dataset out/heads-test/exported.jsonl \
  --kind internal \
  --out out/heads-test/abstain16.pt \
  --hidden-dim 16 >/tmp/spark-ab-train16.txt
grep -q '"state":"succeeded"' /tmp/spark-ab-train16.txt
# Also accept the committed exported fixture
./spark-abstain --live train \
  --dataset examples/fixtures/abstain/labels_exported.jsonl \
  --out out/heads-test/from-shipped.pt \
  --hidden-dim 16 >/tmp/spark-ab-shipped.txt
grep -q '"state":"succeeded"' /tmp/spark-ab-shipped.txt

# Curated corpus validate + synthetic 768 export→train→ask
./spark-abstain --live validate-corpus \
  --dataset examples/fixtures/abstain/corpus_seed.jsonl \
  >/tmp/spark-ab-corpus.txt
grep -q '"state":"ok"' /tmp/spark-ab-corpus.txt
grep -q '"n_abstain"' /tmp/spark-ab-corpus.txt
# Curated seed must be large enough to train a non-toy head.
python3 - <<'PY'
import json
p = "examples/fixtures/abstain/corpus_seed.jsonl"
n = sum(1 for line in open(p) if line.strip() and not line.startswith("#"))
assert n >= 50, n
print("corpus_n", n)
PY
./spark-abstain --live export \
  --dataset examples/fixtures/abstain/corpus_seed.jsonl \
  --source synthetic --hidden-dim 768 \
  --out out/heads-test/synth768.jsonl \
  >/tmp/spark-ab-synth-export.txt
grep -q '"source":"synthetic_backbone"' /tmp/spark-ab-synth-export.txt
grep -q '"hidden_dim":768' /tmp/spark-ab-synth-export.txt
grep -q '"quality":"synthetic_backbone_dim_match"' \
  /tmp/spark-ab-synth-export.txt
./spark-abstain --live train \
  --dataset out/heads-test/synth768.jsonl \
  --out out/heads-test/abstain768.pt \
  --hidden-dim 768 >/tmp/spark-ab-train768.txt
grep -q '"state":"succeeded"' /tmp/spark-ab-train768.txt
grep -q '"hidden_dim":768' /tmp/spark-ab-train768.txt
grep -q '"quality":"synthetic_backbone_dim_match"' \
  /tmp/spark-ab-train768.txt
PYTHONPATH=python python3 - <<'PY'
import torch
from pathlib import Path
from sparklang.abstain.export import synthetic_backbone_hidden
h = synthetic_backbone_hidden(
    "Who is the mayor of Springfield?", 768, 1, seed=42
)
torch.save(torch.tensor(h), Path("out/heads-test/h768.pt"))
print("ok")
PY
./spark-abstain --live ask \
  --prompt "Who is the mayor of Springfield?" \
  --weights out/heads-test/abstain768.pt \
  --hidden out/heads-test/h768.pt \
  --threshold 0.5 \
  >/tmp/spark-ab-ask768.txt
grep -q '"mode":"live"' /tmp/spark-ab-ask768.txt
grep -q '"hidden_source":"file"' /tmp/spark-ab-ask768.txt
grep -q '"abstain":true' /tmp/spark-ab-ask768.txt

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

# Dim-matched ask from toy export (16-d)
PYTHONPATH=python python3 - <<'PY'
import torch
from pathlib import Path
from sparklang.abstain.export import toy_backbone_hidden
h = toy_backbone_hidden(
    "Who is the mayor of Springfield?", 16, seed=42
)
torch.save(torch.tensor(h), Path("out/heads-test/h16.pt"))
print("ok")
PY
./spark-abstain --live ask \
  --prompt "Who is the mayor of Springfield?" \
  --weights out/heads-test/abstain16.pt \
  --hidden out/heads-test/h16.pt \
  >/tmp/spark-ab-ask16.txt
grep -q '"hidden_source":"file"' /tmp/spark-ab-ask16.txt
grep -q '"mode":"live"' /tmp/spark-ab-ask16.txt

# Stub ask still works without weights
SPARK_ABSTAIN_STUB=1 ./spark-abstain --live ask \
  --prompt "Who is the mayor of Springfield?" \
  >/tmp/spark-ab-ask-stub.txt
grep -q '"abstain":true' /tmp/spark-ab-ask-stub.txt

# Contract stub HTTP → live ask (toy dim 16; no GPU)
PYTHONPATH=python python3 tools/spark-abstain/spark_hidden_stub.py \
  --host 127.0.0.1 --port 18765 --dim 16 &
STUB_PID=$!
cleanup_stub() { kill "$STUB_PID" 2>/dev/null || true; }
trap cleanup_stub EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl -sf -X POST "http://127.0.0.1:18765/spark_hidden" \
    -H 'Content-Type: application/json' \
    -d '{"prompt":"ping"}' >/tmp/spark-ab-stub-http.json; then
    break
  fi
  sleep 0.2
done
grep -q '"object": "spark.hidden"\|"object":"spark.hidden"' \
  /tmp/spark-ab-stub-http.json
grep -q '"source": "toy_stub"\|"source":"toy_stub"' \
  /tmp/spark-ab-stub-http.json
SPARK_ABSTAIN_VLLM_URL=http://127.0.0.1:18765 \
  ./spark-abstain --live ask \
  --prompt "Who is the mayor of Springfield?" \
  --weights out/heads-test/abstain16.pt \
  >/tmp/spark-ab-ask-vllm.txt
grep -q '"hidden_source": "vllm_spark_hidden"\|"hidden_source":"vllm_spark_hidden"' \
  /tmp/spark-ab-ask-vllm.txt
grep -q '"mode": "live"\|"mode":"live"' /tmp/spark-ab-ask-vllm.txt
cleanup_stub
trap - EXIT

echo "test-abstain OK"
