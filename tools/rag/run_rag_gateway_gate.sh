#!/usr/bin/env bash
# Offline dry gate for spark-rag-http (embed + retrieve).
# Optional live skipped when gateway/key unavailable.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
fail=0

if [[ ! -x ./spark-rag-http ]]; then
  echo "Building spark-rag-http…"
  make -s spark-rag-http
fi

run_dry_embed() {
  local name="$1" model="$2"
  local out
  out="$(./spark-rag-http --dry --embed --model "$model" \
    --text "Spark is a language for AI workflows" 2>&1)" || {
    echo "FAIL $name (exit $?)"
    echo "$out" | head -20
    fail=1
    return
  }
  echo "$out" | grep -q "dry mode=embed model=$model" || {
    echo "FAIL $name (model line)"
    fail=1
    return
  }
  echo "$out" | grep -q "dry ok (no network)" || {
    echo "FAIL $name (dry ok)"
    fail=1
    return
  }
  echo "$out" | grep -q '"object":"list"' || {
    echo "FAIL $name (fixture json)"
    fail=1
    return
  }
  echo "PASS $name"
}

run_dry_retrieve() {
  local name="$1" project="$2" audience="$3"
  local out
  out="$(./spark-rag-http --dry --retrieve --project "$project" \
    --audience "$audience" --top-k 4 \
    --text "how does dry-run embed work" 2>&1)" || {
    echo "FAIL $name (exit $?)"
    echo "$out" | head -20
    fail=1
    return
  }
  echo "$out" | grep -q "dry mode=retrieve project=$project" || {
    echo "FAIL $name (project line)"
    fail=1
    return
  }
  echo "$out" | grep -q "dry ok (no network)" || {
    echo "FAIL $name (dry ok)"
    fail=1
    return
  }
  echo "$out" | grep -q '"chunks"' || {
    echo "FAIL $name (chunks)"
    fail=1
    return
  }
  echo "$out" | grep -q '"crag"' || {
    echo "FAIL $name (crag field)"
    fail=1
    return
  }
  echo "PASS $name"
}

run_dry_embed dry_embed_rag embed-rag
run_dry_embed dry_embed_alias embed
run_dry_retrieve dry_retrieve_docs docs operator

# Refuse inventing OpenAI.com as primary — dry never needs a key.
if unset SPARK_GATEWAY_KEY OPENAI_API_KEY RAG_GATEWAY_API_KEY; \
  ./spark-rag-http --dry --embed --text "ping" >/dev/null 2>&1; then
  echo "PASS dry_no_key"
else
  echo "FAIL dry_no_key"
  fail=1
fi

# Example dry-run through ./spark when built.
if [[ -x ./spark ]]; then
  if ./spark --dry-run examples/retrieve_embed.spark >/dev/null 2>&1; then
    echo "PASS spark_dry_retrieve_embed"
  else
    echo "FAIL spark_dry_retrieve_embed"
    fail=1
  fi
fi

live_skip() {
  echo "SKIP live_rag ($1)"
}

if [[ "${SPARK_RAG_GATEWAY_LIVE:-0}" == "1" ]]; then
  key="${SPARK_GATEWAY_KEY:-${OPENAI_API_KEY:-}}"
  base="${AI_GATEWAY_URL:-http://127.0.0.1:4000}"
  if [[ -z "$key" ]]; then
    live_skip "no SPARK_GATEWAY_KEY / OPENAI_API_KEY"
  elif ! curl -sS -m 2 -o /dev/null -w "%{http_code}" \
    "${base%/}/v1/models" 2>/dev/null | grep -qE '^[0-9]+$'; then
    live_skip "gateway unreachable at $base"
  else
    out="$(./spark-rag-http --live --embed --model embed-rag \
      --text "Spark language" 2>&1)" || {
      echo "FAIL live_embed"
      echo "$out" | head -20
      fail=1
      out=""
    }
    if [[ -n "$out" ]]; then
      echo "$out" | grep -q embedding && echo "PASS live_embed" || {
        [[ -n "$(echo "$out" | tr -d '[:space:]')" ]] && \
          echo "PASS live_embed (nonempty)" || {
          echo "FAIL live_embed (empty)"
          fail=1
        }
      }
    fi
  fi
else
  live_skip "set SPARK_RAG_GATEWAY_LIVE=1 to opt in"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "rag-gateway gate: FAIL"
  exit 1
fi
echo "rag-gateway gate: OK"
exit 0
