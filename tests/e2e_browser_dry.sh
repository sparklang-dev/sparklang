#!/usr/bin/env bash
# Browser E2E — dry language path only (no display, no --live GUI).
# Live product entry remains: spark-browser → make run →
#   ./spark --live browser/run.spark
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
make -s spark companions

fail=0
check() {
  local name="$1" file="$2" needle="$3"
  out="$(./spark --dry-run "$file" 2>&1)" || {
    echo "FAIL $name: exit non-zero"
    fail=1
    return
  }
  if echo "$out" | grep -qE "$needle"; then
    echo "PASS $name"
  else
    echo "FAIL $name: missing '$needle'"
    echo "$out" | head -20
    fail=1
  fi
}

check_fail() {
  local name="$1" file="$2" needle="$3"
  set +e
  out="$(./spark --dry-run "$file" 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL $name: expected non-zero exit"
    fail=1
    return
  fi
  if echo "$out" | grep -qE "$needle"; then
    echo "PASS $name"
  else
    echo "FAIL $name: missing '$needle' (rc=$rc)"
    echo "$out" | head -20
    fail=1
  fi
}

echo "=== e2e-browser dry (no display) ==="

rm -rf out/browser
check browser_main examples/browser_main.spark '\[browser\]'
check browser_goto examples/browser_main.spark '"op":"goto"'
check browser_mitm_en examples/browser_main.spark '"op":"enable"'
check browser_har examples/browser_main.spark 'byte_written'
test -f out/browser/session.json \
  && test -f out/browser/mitm.json \
  && test -f out/browser/session.har \
  && grep -q 'example.com' out/browser/session.har \
  && grep -q 'cdn.example.com' out/browser/session.har \
  && grep -q 'api.example.com' out/browser/session.har \
  && grep -q 'demo-multiflow' out/browser/session.har \
  && grep -q '"log"' out/browser/session.har \
  && echo "PASS browser-artifacts" || {
  echo "FAIL browser-artifacts"
  fail=1
}

check browser_quic examples/browser_quic.spark 'mitm.quic.smoke'
check browser_flags examples/browser_mitm.spark 'disable_quic.:false'
check browser_cdp examples/browser_cdp.spark 'cdp\.status'
check browser_cdp_nav examples/browser_cdp.spark 'cdp\.navigate'
check browser_cdp_eval examples/browser_cdp.spark 'cdp\.evaluate'
check browser_cdp_shot examples/browser_cdp.spark 'cdp\.screenshot'

check browser_show examples/browser_show.spark '"op":"show"'
test -f out/browser/show.json && echo "PASS browser-show-json" || {
  echo "FAIL browser-show-json"; fail=1
}
check_fail browser_show_missing examples/neg/browser_show_missing.spark \
  "cannot open image"


# Product live program must refuse GUI under --dry-run
SB_RUN="../spark-browser/browser/run.spark"
if [[ -f "$SB_RUN" ]]; then
  check_fail run_spark_gui_dry "$SB_RUN" "requires --live"
else
  echo "WARN missing $SB_RUN (skip live-program dry check)"
fi

printf 'browser gui\n' > examples/neg/browser_gui_dry.spark
check_fail browser_gui_dry examples/neg/browser_gui_dry.spark \
  "requires --live"
printf 'browser goto "https://x.test/"\n' \
  > examples/neg/browser_no_session.spark
check_fail browser_no_session examples/neg/browser_no_session.spark \
  "session required"
printf 'mitm har export "out/browser/x.har"\n' \
  > examples/neg/mitm_no_enable.spark
check_fail mitm_no_enable examples/neg/mitm_no_enable.spark \
  "mitm enable"

# Makefile contract: only Spark entry for live
grep -q 'browser/run.spark' ../spark-browser/Makefile \
  && grep -q 'spark --live' ../spark-browser/Makefile \
  && echo "PASS makefile-live-entrypoint" || {
  echo "FAIL makefile-live-entrypoint"
  fail=1
}
grep -q 'examples/browser_main.spark' ../spark-browser/Makefile \
  && echo "PASS makefile-dry-entrypoint" || {
  echo "FAIL makefile-dry-entrypoint"
  fail=1
}

if [[ "$fail" -ne 0 ]]; then
  echo "E2E-BROWSER DRY FAILED"
  exit 1
fi
echo "E2E-BROWSER DRY OK"
