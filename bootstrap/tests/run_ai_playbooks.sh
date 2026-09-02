#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
PB="bootstrap/fixtures/playbooks"
make -s spark-bootstrap
fail=0
check() { local n="$1" f="$2" nd="$3" out; out="$(./spark-bootstrap --dry-run "$f" 2>&1)" || { echo FAIL $n; fail=1; return; }; echo "$out"|grep -qE "$nd" && echo PASS $n || { echo FAIL $n; echo "$out"|head -12; fail=1; }; }
# use auto must keep prior model — never invent gateway aliases from text
check_prior() {
  local n="$1" f="$2" nd="$3" out
  out="$(./spark-bootstrap --dry-run "$f" 2>&1)" || {
    echo FAIL $n; fail=1; return
  }
  echo "$out" | grep -q 'prior .* (no alias pick)' &&
    echo "$out" | grep -qvE 'auto→(fast|code)' &&
    echo "$out" | grep -qE "$nd" && echo PASS $n || {
    echo FAIL $n; echo "$out"|head -12; fail=1
  }
}
check explain_code "$PB/explain_code.spark" 'Gravity pulls'
check fix_test_failure "$PB/fix_test_failure.spark" 'Fix: update'
check add_api_endpoint "$PB/add_api_endpoint.spark" 'GET /health'
check refactor_rename "$PB/refactor_rename.spark" 'Rename consistently'
check write_unit_test "$PB/write_unit_test.spark" 'def test_add'
check debug_error_message "$PB/debug_error_message.spark" 'stack trace line 42'
check classify_and_reply "$PB/classify_and_reply.spark" 'Happy to help'
check review_and_suggest "$PB/review_and_suggest.spark" 'Fix: update'
check pipeline "$PB/pipeline_summarize_explain.spark" 'pipeline'
check_prior use_auto "$PB/use_auto_explicit.spark" 'Gravity pulls'
check_prior use_auto_bc_fast selfhost/fixtures/use_auto_fast.spark \
  'Gravity pulls'
check_prior use_auto_bc_code selfhost/fixtures/use_auto_code.spark \
  'Fix: update'
[[ $fail -eq 0 ]] && echo "ai-playbook tests OK" || exit 1
