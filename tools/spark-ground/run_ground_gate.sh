#!/usr/bin/env bash
# Offline gate: wrong expect abstains; match passes; adapter attach.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [[ ! -x ./spark-ground ]]; then
  echo "Building spark-ground…"
  make -s spark-ground
fi

FX=examples/fixtures/ground
fail=0

echo "== wrong expect → abstain (exit 2) =="
set +e
./spark-ground ask \
  --prompt "What is the dryer start price right now?" \
  --sot-ok \
  --expect "2.50" \
  --candidate "9.99" \
  --out /tmp/spark-ground-wrong.json
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL: expected exit 2, got $rc" >&2
  fail=1
fi
grep -q '"abstain": true' /tmp/spark-ground-wrong.json
grep -q expect_equal_miss /tmp/spark-ground-wrong.json

echo "== matching expect → pass =="
./spark-ground ask \
  --prompt "What is the dryer start price right now?" \
  --sot-ok \
  --expect "2.50" \
  --candidate "2.50" \
  --out /tmp/spark-ground-ok.json
grep -q '"abstain": false' /tmp/spark-ground-ok.json
grep -q '"reason": "verified"' /tmp/spark-ground-ok.json

echo "== inventable without SoT → abstain =="
set +e
./spark-ground ask \
  --prompt "Who is the mayor of Springfield?" \
  --candidate "Mayor Invented" \
  --expect "Mayor Invented" \
  --out /tmp/spark-ground-invent.json
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL: inventable should abstain, got $rc" >&2
  fail=1
fi
grep -q outer_verify /tmp/spark-ground-invent.json

echo "== schema fail → abstain =="
set +e
./spark-ground verify \
  --candidate '{"price_usd":"nope"}' \
  --schema "$FX/want_price.schema.json" \
  --out /tmp/spark-ground-schema.json
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL: schema miss should exit 2, got $rc" >&2
  fail=1
fi

echo "== schema pass =="
./spark-ground verify \
  --candidate '{"price_usd":2.5,"source":"fixture"}' \
  --schema "$FX/want_price.schema.json" \
  --out /tmp/spark-ground-schema-ok.json
grep -q '"abstain": false' /tmp/spark-ground-schema-ok.json

echo "== adapter-attach manifest =="
./spark-ground adapter-attach \
  --base qwen \
  --keep-existing out/train/existing-lora \
  --add out/train/job-dry-001/adapter.bin \
  --add out/heads/abstain.pt \
  --kind adapter \
  --out out/ground/adapter_manifest.json \
  | tee /tmp/spark-ground-adapt.json
grep -q keep_special_training /tmp/spark-ground-adapt.json
grep -q '"never": "6000"' /tmp/spark-ground-adapt.json

echo "== unit tests =="
PYTHONPATH=python python3 tools/spark-ground/test_ground.py

if [[ "$fail" -ne 0 ]]; then
  echo "spark-ground gate FAILED" >&2
  exit 1
fi
echo "spark-ground gate OK"
