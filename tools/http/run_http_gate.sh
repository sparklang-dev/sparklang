#!/usr/bin/env bash
# Offline dry gate for spark-http (http get / http post).
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
  local out
  out="$(./spark --dry-run examples/http_get.spark 2>&1)" || {
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
run_spark_dry dry_spark_http_get

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
else
  echo "SKIP live_http_get (set SPARK_HTTP_LIVE=1)"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "test-http FAIL"
  exit 1
fi
echo "test-http OK (dry)"
exit 0
