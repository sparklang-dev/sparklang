#!/usr/bin/env bash
# Offline dry gate for spark-ask-http (Bifrost aliases).
# Optional --live probe skipped when gateway/key unavailable.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
fail=0

if [[ ! -x ./spark-ask-http ]]; then
  echo "Building spark-ask-http…"
  make -s spark-ask-http
fi

run_dry() {
  local name="$1" model="$2" prompt="$3" expect="$4"
  local out
  out="$(./spark-ask-http --dry --model "$model" --prompt "$prompt" 2>&1)" || {
    echo "FAIL $name (exit $?)"
    echo "$out" | head -20
    fail=1
    return
  }
  echo "$out" | grep -q "dry model=$expect" || {
    echo "FAIL $name (expected model=$expect)"
    echo "$out" | head -20
    fail=1
    return
  }
  echo "$out" | grep -q "dry ok (no network)" || {
    echo "FAIL $name (missing dry ok)"
    fail=1
    return
  }
  echo "PASS $name"
}

run_dry dry_fast fast "Reply with exactly one word: pong" fast
run_dry dry_code code "Fix this test failure: AssertionError" code
run_dry dry_best best "Explain gravity in one sentence" best
run_dry dry_auto_fast auto "Summarize this paragraph briefly" fast
run_dry dry_auto_code auto "Fix this test failure: expected 3 got 2" code

# Refuse inventing OpenAI.com as primary — dry never needs a key.
if unset SPARK_GATEWAY_KEY OPENAI_API_KEY; \
  ./spark-ask-http --dry --model fast --prompt "ping" >/dev/null 2>&1; then
  echo "PASS dry_no_key"
else
  echo "FAIL dry_no_key"
  fail=1
fi

# Optional live: skip if gateway down or no key (not a CI fail).
live_skip() {
  echo "SKIP live_ask ($1)"
}

if [[ "${SPARK_ASK_GATEWAY_LIVE:-0}" == "1" ]]; then
  key="${SPARK_GATEWAY_KEY:-${OPENAI_API_KEY:-}}"
  base="${AI_GATEWAY_URL:-http://127.0.0.1:4000}"
  if [[ -z "$key" ]]; then
    live_skip "no SPARK_GATEWAY_KEY / OPENAI_API_KEY"
  elif ! curl -sS -m 2 -o /dev/null -w "%{http_code}" \
    "${base%/}/v1/models" 2>/dev/null | grep -qE '^[0-9]+$'; then
    live_skip "gateway unreachable at $base"
  else
    out="$(./spark-ask-http --model fast --prompt \
      "Reply with exactly one word: pong" 2>&1)" || {
      echo "FAIL live_fast"
      echo "$out" | head -20
      fail=1
      out=""
    }
    if [[ -n "$out" ]]; then
      echo "$out" | grep -qiE 'pong|ok|yes|here' && \
        echo "PASS live_fast" || {
        # Accept any non-empty model reply as live path proof
        [[ -n "$(echo "$out" | tr -d '[:space:]')" ]] && \
          echo "PASS live_fast (nonempty reply)" || {
          echo "FAIL live_fast (empty)"
          fail=1
        }
      }
    fi
  fi
else
  live_skip "set SPARK_ASK_GATEWAY_LIVE=1 to opt in"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "ask-gateway gate: FAIL"
  exit 1
fi
echo "ask-gateway gate: OK"
exit 0
