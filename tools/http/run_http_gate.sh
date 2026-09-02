#!/usr/bin/env bash
# Offline dry gate for spark-http (http get / http post + auth/retries).
# Optional live: SPARK_HTTP_LIVE=1 (real network).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
fail=0

if [[ ! -x ./spark-http ]]; then
  echo "Building spark-http…"
  make -s spark-http
fi

run_dry_get() {
  local name="$1"
  local out
  out="$(./spark-http --dry --get \
    --url "https://example.com/" \
    --fixture examples/fixtures/http/get_ok.json \
    --timeout 5 2>&1)" || {
    echo "FAIL $name (exit $?)"
    echo "$out" | head -20
    fail=1
    return 0
  }
  echo "$out" | grep -q "dry mode=get" || {
    echo "FAIL $name (mode line)"
    fail=1
    return 0
  }
  echo "$out" | grep -q "dry ok (no network)" || {
    echo "FAIL $name (dry ok)"
    fail=1
    return 0
  }
  echo "$out" | grep -q '"source": "fixture"' || {
    echo "FAIL $name (fixture json)"
    fail=1
    return 0
  }
  echo "PASS $name"
}

run_dry_auth_retries() {
  local name="$1"
  local out
  out="$(./spark-http --dry --get \
    --url "https://example.com/" \
    --fixture examples/fixtures/http/get_ok.json \
    --bearer "dry-token-not-sent" \
    --retries 2 --backoff 100 --timeout 5 2>&1)" || {
    echo "FAIL $name (exit $?)"
    echo "$out" | head -20
    fail=1
    return 0
  }
  echo "$out" | grep -q "auth=bearer" || {
    echo "FAIL $name (auth)"
    fail=1
    return 0
  }
  echo "$out" | grep -q "retries=2" || {
    echo "FAIL $name (retries)"
    fail=1
    return 0
  }
  echo "$out" | grep -q "backoff_ms=100" || {
    echo "FAIL $name (backoff)"
    fail=1
    return 0
  }
  echo "$out" | grep -q "dry ok (no network)" || {
    echo "FAIL $name (dry ok)"
    fail=1
    return 0
  }
  # Token must not appear on stderr (redacted to auth=bearer).
  if echo "$out" | grep -q "dry-token-not-sent"; then
    echo "FAIL $name (token leaked)"
    fail=1
    return 0
  fi
  echo "PASS $name"
}

run_dry_post() {
  local name="$1"
  local out
  out="$(./spark-http --dry --post \
    --url "https://example.com/api" \
    --fixture examples/fixtures/http/post_ok.json \
    --body '{"ping":true}' \
    --timeout 5 2>&1)" || {
    echo "FAIL $name (exit $?)"
    echo "$out" | head -20
    fail=1
    return 0
  }
  echo "$out" | grep -q "dry mode=post" || {
    echo "FAIL $name (mode line)"
    fail=1
    return 0
  }
  echo "$out" | grep -q "dry ok (no network)" || {
    echo "FAIL $name (dry ok)"
    fail=1
    return 0
  }
  echo "$out" | grep -q '"source": "fixture"' || {
    echo "FAIL $name (fixture json)"
    fail=1
    return 0
  }
  echo "PASS $name"
}

run_dry_missing() {
  local name="$1"
  local rc=0
  set +e
  ./spark-http --dry --get --url "https://example.com/" \
    --fixture examples/fixtures/http/does_not_exist.json \
    >/tmp/spark-http-miss.out 2>/tmp/spark-http-miss.err
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL $name (expected non-zero)"
    fail=1
    return 0
  fi
  if ! grep -q "fixture missing" /tmp/spark-http-miss.err; then
    echo "FAIL $name (missing message)"
    fail=1
    return 0
  fi
  echo "PASS $name"
}

run_spark_dry() {
  local name="$1"
  local file="$2"
  local out
  out="$(./spark --dry-run "$file" 2>&1)" || {
    echo "FAIL $name (exit $?)"
    echo "$out" | head -30
    fail=1
    return 0
  }
  echo "$out" | grep -q '\[http\]' || {
    echo "FAIL $name (banner)"
    fail=1
    return 0
  }
  echo "$out" | grep -q '"source": "fixture"' || {
    echo "FAIL $name (body)"
    fail=1
    return 0
  }
  echo "PASS $name"
}

run_dry_get dry_http_get
run_dry_post dry_http_post
run_dry_missing dry_http_missing_fixture
run_dry_auth_retries dry_http_auth_retries
run_spark_dry dry_spark_http_get examples/http_get.spark
run_spark_dry dry_spark_http_auth examples/http_get_auth.spark

if [[ "${SPARK_HTTP_LIVE:-}" == "1" ]]; then
  set +e
  live_out="$(./spark-http --live --get \
    --url "https://example.com/" --timeout 10 2>&1)"
  live_rc=$?
  set -e
  if [[ "$live_rc" -ne 0 ]]; then
    echo "FAIL live_http_get (exit $live_rc)"
    echo "$live_out" | head -20
    fail=1
  elif ! echo "$live_out" | grep -q '"mode":"live"'; then
    echo "FAIL live_http_get (envelope)"
    fail=1
  else
    echo "PASS live_http_get"
  fi

  set +e
  auth_out="$(./spark-http --live --get \
    --url "https://httpbin.org/bearer" \
    --bearer "spark-gate-token" --timeout 15 2>&1)"
  auth_rc=$?
  set -e
  if [[ "$auth_rc" -ne 0 ]]; then
    echo "FAIL live_http_bearer (exit $auth_rc)"
    echo "$auth_out" | head -20
    fail=1
  elif ! echo "$auth_out" | grep -q '"auth":"bearer"'; then
    echo "FAIL live_http_bearer (auth field)"
    fail=1
  elif ! echo "$auth_out" | grep -q 'authenticated'; then
    echo "FAIL live_http_bearer (body)"
    fail=1
  else
    echo "PASS live_http_bearer"
  fi

  set +e
  retry_out="$(./spark-http --live --get \
    --url "https://httpbin.org/status/503" \
    --retries 2 --backoff 50 --timeout 15 2>&1)"
  retry_rc=$?
  set -e
  if [[ "$retry_rc" -eq 0 ]]; then
    echo "FAIL live_http_retries (expected non-zero)"
    fail=1
  elif ! echo "$retry_out" | grep -q 'attempt=3/3'; then
    echo "FAIL live_http_retries (attempts)"
    echo "$retry_out" | head -20
    fail=1
  elif ! echo "$retry_out" | grep -q 'retryable'; then
    echo "FAIL live_http_retries (retryable)"
    fail=1
  else
    echo "PASS live_http_retries"
  fi
else
  echo "SKIP live_http_get (set SPARK_HTTP_LIVE=1)"
  echo "SKIP live_http_bearer (set SPARK_HTTP_LIVE=1)"
  echo "SKIP live_http_retries (set SPARK_HTTP_LIVE=1)"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "test-http FAIL"
  exit 1
fi
echo "test-http OK (dry)"
exit 0
