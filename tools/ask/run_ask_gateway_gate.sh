#!/usr/bin/env bash
# Offline dry gate for spark-ask-http (explicit model ids).
# Optional --live probe skipped when gateway/key unavailable.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
fail=0

if [[ ! -x ./spark-ask-http ]]; then
  echo "Building spark-ask-http…"
  make -s spark-ask-http
fi


run_dry_stream() {
  local out
  out="$(./spark-ask-http --dry --stream --model fixtures/tiny-lm \
    --prompt "ping" 2>&1)" || {
    echo "FAIL dry_stream (exit $?)"
    echo "$out" | head -20
    fail=1
    return
  }
  echo "$out" | grep -q "stream=1" || {
    echo "FAIL dry_stream (missing stream=1)"
    echo "$out" | head -20
    fail=1
    return
  }
  echo "PASS dry_stream"
}

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

run_refuse_auto() {
  local out rc=0
  out="$(./spark-ask-http --dry --model auto --prompt "ping" 2>&1)" || rc=$?
  if [[ "$rc" -ne 0 ]] && echo "$out" | grep -qiE 'refuse|auto'; then
    echo "PASS dry_refuse_auto"
  else
    echo "FAIL dry_refuse_auto (rc=$rc)"
    echo "$out" | head -20
    fail=1
  fi
}

run_dry dry_explicit fixtures/tiny-lm "Reply with exactly one word: pong" fixtures/tiny-lm
run_dry dry_path org/local-lm "Explain gravity in one sentence" org/local-lm
# Explicit gateway route names remain allowed when the user names them —
# only the picker token "auto" is refused.
run_dry dry_named_fast fast "Reply with exactly one word: pong" fast
run_refuse_auto
run_dry_stream

# Rollup from fixture jsonl (no network, no invent).
run_rollup() {
  local tf out
  tf="$(mktemp /tmp/spark-ask-account-test.XXXXXX)"
  printf '%s\n' \
    '{"latency_ms":10,"prompt_tokens":2,"completion_tokens":3,"total_tokens":5}' \
    '{"latency_ms":5,"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}' \
    > "$tf"
  out="$(./spark-ask-http --rollup --account-file "$tf" 2>&1)" || {
    echo "FAIL rollup (exit $?)"
    echo "$out" | head -20
    fail=1
    rm -f "$tf"
    return
  }
  echo "$out" | grep -q 'asks=2' \
    && echo "$out" | grep -q 'latency_ms=15' \
    && echo "$out" | grep -q 'prompt_tokens=3' \
    && echo "$out" | grep -q 'total_tokens=7' || {
    echo "FAIL rollup (sums)"
    echo "$out" | head -20
    fail=1
    rm -f "$tf"
    return
  }
  echo "PASS rollup"
  rm -f "$tf"
}
run_rollup

# Missing account file is asks=0, not a crash.
if ./spark-ask-http --rollup --account-file \
  /tmp/spark-ask-account-missing-$$.jsonl 2>&1 | grep -q 'asks=0'; then
  echo "PASS rollup_missing"
else
  echo "FAIL rollup_missing"
  fail=1
fi

# Refuse inventing OpenAI.com as primary — dry never needs a key.
if unset SPARK_GATEWAY_KEY OPENAI_API_KEY; \
  ./spark-ask-http --dry --model fixtures/tiny-lm --prompt "ping" >/dev/null 2>&1; then
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
    out="$(./spark-ask-http --model fixtures/tiny-lm --prompt \
      "Reply with exactly one word: pong" 2>&1)" || {
      echo "FAIL live_explicit"
      echo "$out" | head -20
      fail=1
      out=""
    }
    if [[ -n "$out" ]]; then
      echo "$out" | grep -qiE 'pong|ok|yes|here' && \
        echo "PASS live_explicit" || {
        [[ -n "$(echo "$out" | tr -d '[:space:]')" ]] && \
          echo "PASS live_explicit (nonempty reply)" || {
          echo "FAIL live_explicit (empty)"
          fail=1
        }
      }
      echo "$out" | grep -qE '\[accounting\] latency_ms=[1-9]' \
        && echo "PASS live_latency" || {
        echo "$out" | grep -q '\[accounting\] latency_ms=' \
          && echo "PASS live_latency (zero or present)" || {
          echo "FAIL live_latency (no accounting line)"
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
