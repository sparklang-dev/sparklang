#!/usr/bin/env bash
# Lex goldens: selfhost/spark-lex and spark-bootstrap --lex.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

make -s selfhost-lex spark-bootstrap

fixtures=(mini ops bootstrap_ops review_voice browser_dry ide_dry \
  classify_dry let_dry ask_dry engine_dry ide_keys_dry binary_dry \
  network_dry encrypt_dry cuda_dry os_dry pcie_dry rag_dry)

for f in "${fixtures[@]}"; do
  ./selfhost/spark-lex "selfhost/fixtures/${f}.spark" \
    > "/tmp/spark-lex-${f}.jsonl"
  diff -u "selfhost/expected_${f}.tokens.jsonl" \
    "/tmp/spark-lex-${f}.jsonl"
  ./spark-bootstrap --lex "selfhost/fixtures/${f}.spark" \
    > "/tmp/spark-boot-lex-${f}.jsonl"
  diff -u "selfhost/expected_${f}.tokens.jsonl" \
    "/tmp/spark-boot-lex-${f}.jsonl"
done

./spark --dry-run selfhost/token_kinds.spark >/dev/null
./spark --dry-run selfhost/lexer.spark >/dev/null
./spark --dry-run selfhost/grammar.spark >/dev/null
./spark --dry-run selfhost/parser.spark >/dev/null
# network_dry / encrypt_dry: GAS exits 1 without CAP_NET_RAW /
# spark-enc-gateway — lex goldens above are the Phase 2 gate.
gas_skip=(network_dry encrypt_dry)
for f in "${fixtures[@]}"; do
  skip=0
  for s in "${gas_skip[@]}"; do
    [[ "$f" == "$s" ]] && skip=1 && break
  done
  if [[ "$skip" -eq 1 ]]; then
    echo "SKIP gas_dry_${f} (GAS fail-loud without cap/companion)"
    continue
  fi
  ./spark --dry-run "selfhost/fixtures/${f}.spark" >/dev/null
done
echo "test-selfhost-lex OK"
