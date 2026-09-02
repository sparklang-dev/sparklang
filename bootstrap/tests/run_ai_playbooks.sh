#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
PB="bootstrap/fixtures/playbooks"
make -s spark-bootstrap
fail=0
check_af() { local n="$1" f="$2" nd="$3" out; out="$(./spark-bootstrap --dry-run "$f" 2>&1)" || { echo FAIL $n; fail=1; return; }; echo "$out"|grep -q 'auto→fast' && echo "$out"|grep -qE "$nd" && echo PASS $n || { echo FAIL $n; echo "$out"|head -12; fail=1; }; }
check_ac() { local n="$1" f="$2" nd="$3" out; out="$(./spark-bootstrap --dry-run "$f" 2>&1)" || { echo FAIL $n; fail=1; return; }; echo "$out"|grep -q 'auto→code' && echo "$out"|grep -qE "$nd" && echo PASS $n || { echo FAIL $n; echo "$out"|head -12; fail=1; }; }
check() { local n="$1" f="$2" nd="$3" out; out="$(./spark-bootstrap --dry-run "$f" 2>&1)" || { echo FAIL $n; fail=1; return; }; echo "$out"|grep -qE "$nd" && echo PASS $n || { echo FAIL $n; fail=1; }; }
check_af explain_code "$PB/explain_code.spark" 'Gravity pulls'
check_ac fix_test_failure "$PB/fix_test_failure.spark" 'Fix: update'
check_ac add_api_endpoint "$PB/add_api_endpoint.spark" 'GET /health'
check_ac refactor_rename "$PB/refactor_rename.spark" 'Rename consistently'
check_ac write_unit_test "$PB/write_unit_test.spark" 'def test_add'
check_ac debug_error_message "$PB/debug_error_message.spark" 'stack trace line 42'
check_af classify_and_reply "$PB/classify_and_reply.spark" 'Happy to help'
check_ac review_and_suggest "$PB/review_and_suggest.spark" 'Fix: update'
check pipeline "$PB/pipeline_summarize_explain.spark" 'pipeline'
check_af use_auto "$PB/use_auto_explicit.spark" 'Gravity pulls'
check banner "$PB/use_auto_explicit.spark" '\[model\] auto'
# BC path: use auto must compile + resolve (not tree-walk fallback).
check_bc_af() {
  local n="$1" f="$2" nd="$3" out
  out="$(./spark-bootstrap --dry-run "$f" 2>&1)" || {
    echo FAIL $n; fail=1; return
  }
  echo "$out" | grep -q 'dry-run via bytecode VM' &&
    echo "$out" | grep -q 'auto→fast' &&
    echo "$out" | grep -qE "$nd" && echo PASS $n || {
    echo FAIL $n; echo "$out" | head -12; fail=1
  }
}
check_bc_ac() {
  local n="$1" f="$2" nd="$3" out
  out="$(./spark-bootstrap --dry-run "$f" 2>&1)" || {
    echo FAIL $n; fail=1; return
  }
  echo "$out" | grep -q 'dry-run via bytecode VM' &&
    echo "$out" | grep -q 'auto→code' &&
    echo "$out" | grep -qE "$nd" && echo PASS $n || {
    echo FAIL $n; echo "$out" | head -12; fail=1
  }
}
check_bc_af use_auto_bc_fast selfhost/fixtures/use_auto_fast.spark \
  'Gravity pulls'
check_bc_ac use_auto_bc_code selfhost/fixtures/use_auto_code.spark \
  'Fix: update'
[[ $fail -eq 0 ]] && echo "ai-playbook tests OK" || exit 1
