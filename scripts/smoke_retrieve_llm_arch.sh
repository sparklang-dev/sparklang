#!/usr/bin/env bash
# Live SparkLang retrieve smoke against ragindex project
# llm-architecture-training (series just ingested).
#
# Dry-first: companion --dry never dials. Live requires
# RAG_GATEWAY_URL + RAG_GATEWAY_API_KEY (or SPARK_GATEWAY_KEY).
# Never prints key values.
#
# Usage:
#   ./scripts/smoke_retrieve_llm_arch.sh          # dry + live if key present
#   SPARK_RETRIEVE_SMOKE_LIVE=0 ./scripts/...     # dry only
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="${SPARK_RETRIEVE_PROJECT:-llm-architecture-training}"
AUDIENCE="${SPARK_RETRIEVE_AUDIENCE:-operator}"
TOP_K="${SPARK_RETRIEVE_TOP_K:-3}"
LIVE_OPT="${SPARK_RETRIEVE_SMOKE_LIVE:-1}"

if [[ ! -x ./spark-rag-http ]]; then
  echo "Building spark-rag-http…"
  make -s spark-rag-http
fi

# Load rag-gateway env if present (no echo of values).
if [[ -f "${HOME}/.config/rag-gateway/rag-gateway.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${HOME}/.config/rag-gateway/rag-gateway.env"
  set +a
fi
export RAG_GATEWAY_URL="${RAG_GATEWAY_URL:-http://127.0.0.1:4620}"

QUERIES=(
  "What is CRAG-lite in the ablation ladder?"
  "QLoRA fine-tuning on a single GPU"
  "MCP tool poisoning and rug pull"
)

echo "== dry retrieve ($PROJECT) =="
for q in "${QUERIES[@]}"; do
  out="$(./spark-rag-http --dry --retrieve --project "$PROJECT" \
    --audience "$AUDIENCE" --top-k "$TOP_K" --text "$q" 2>&1)" || {
    echo "FAIL dry: $q"
    echo "$out" | head -20
    exit 1
  }
  echo "$out" | grep -q "dry mode=retrieve project=$PROJECT" || {
    echo "FAIL dry banner: $q"; exit 1; }
  echo "PASS dry: ${q:0:48}…"
done

key="${RAG_GATEWAY_API_KEY:-${SPARK_GATEWAY_KEY:-}}"
if [[ "$LIVE_OPT" != "1" ]]; then
  echo "SKIP live (SPARK_RETRIEVE_SMOKE_LIVE=$LIVE_OPT)"
  exit 0
fi
if [[ -z "$key" ]]; then
  echo "SKIP live (no RAG_GATEWAY_API_KEY / SPARK_GATEWAY_KEY)"
  exit 0
fi

echo "== live retrieve ($PROJECT via $RAG_GATEWAY_URL) =="
fail=0
for q in "${QUERIES[@]}"; do
  out="$(./spark-rag-http --live --retrieve --project "$PROJECT" \
    --audience "$AUDIENCE" --top-k "$TOP_K" --text "$q" 2>&1)" || {
    rc=$?
    if [[ "$rc" -eq 4 ]] || echo "$out" | grep -qi 'credential'; then
      echo "FAIL live: credential unavailable (no routing invent)"
      exit 4
    fi
    echo "FAIL live: $q (rc=$rc)"
    echo "$out" | head -30
    fail=1
    continue
  }
  # Must mention the project or return real chunks (not the docs fixture).
  if echo "$out" | grep -qF 'dry-run fixture'; then
    echo "FAIL live: got dry fixture for: $q"
    fail=1
    continue
  fi
  if ! echo "$out" | grep -qiE 'chunk|"content"|CRAG|QLoRA|poison|LoRA|ablation'; then
    echo "FAIL live: empty/unrelated for: $q"
    echo "$out" | head -20
    fail=1
    continue
  fi
  echo "PASS live: ${q:0:48}…"
  # One-line hit digest (no secrets).
  echo "$out" | tr '\n' ' ' | grep -oE 'part-[0-9]+[^"[:space:]]*' | head -3 \
    | sed 's/^/  hit: /' || true
done

if [[ "$fail" -ne 0 ]]; then
  echo "smoke_retrieve_llm_arch: FAIL"
  exit 1
fi
echo "smoke_retrieve_llm_arch: OK"
exit 0
