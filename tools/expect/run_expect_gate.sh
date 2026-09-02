#!/usr/bin/env bash
# Offline dry gate for expect equal/contains (pass/fail).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
fail=0

if [[ ! -x ./spark-expect ]]; then
  echo "Building spark-expect…"
  make -s spark-expect
fi
if [[ ! -x ./spark ]]; then
  echo "Building spark…"
  make -s spark
fi

FX=examples/fixtures/eval

expect_ok() {
  local name="$1"
  shift
  local out
  if ! out="$("$@" 2>&1)"; then
    echo "FAIL $name (expected exit 0)"
    echo "$out" | head -20
    fail=1
    return 0
  fi
  if ! echo "$out" | grep -qF '[expect] pass'; then
    echo "FAIL $name (missing pass line)"
    echo "$out" | head -20
    fail=1
    return 0
  fi
  echo "PASS $name"
}

expect_fail() {
  local name="$1"
  local want="$2"
  shift 2
  local out rc=0
  set +e
  out="$("$@" 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL $name (expected non-zero)"
    echo "$out" | head -20
    fail=1
    return 0
  fi
  if ! echo "$out" | grep -qF "$want"; then
    echo "FAIL $name (wrong reason, want: $want)"
    echo "$out" | head -20
    fail=1
    return 0
  fi
  echo "PASS $name"
}

# --- companion direct -------------------------------------------------
expect_ok equal_literal \
  ./spark-expect --dry --mode equal --name answer \
  --got "Ada Lovelace" --want "Ada Lovelace"

expect_ok contains_literal \
  ./spark-expect --dry --mode contains --name answer \
  --got "Ada Lovelace" --want "Lovelace"

expect_ok equal_fixture \
  ./spark-expect --dry --mode equal --name answer \
  --got "Ada Lovelace" --fixture "$FX/want_name.txt"

expect_fail equal_mismatch \
  'got "Ada" want "Bob"' \
  ./spark-expect --dry --mode equal --name answer \
  --got "Ada" --want "Bob"

expect_fail contains_miss \
  'got "Ada" want "Bob"' \
  ./spark-expect --dry --mode contains --name answer \
  --got "Ada" --want "Bob"

expect_fail fixture_missing \
  'fixture missing' \
  ./spark-expect --dry --mode equal --name answer \
  --got "Ada" --fixture "$FX/does_not_exist.txt"

# --- through the assembly VM ------------------------------------------
vm_ok() {
  local out
  if ! out="$(./spark --dry-run examples/expect_pass.spark 2>&1)"; then
    echo "FAIL vm_expect_pass (exit $?)"
    echo "$out" | head -30
    fail=1
    return 0
  fi
  echo "$out" | grep -q '\[expect\] pass equal answer' || {
    echo "FAIL vm_expect_pass (equal)"; fail=1; return 0; }
  echo "$out" | grep -q '\[expect\] pass contains answer' || {
    echo "FAIL vm_expect_pass (contains)"; fail=1; return 0; }
  echo "$out" | grep -q '\[expect\] pass equal answer' || true
  echo "$out" | grep -q 'fixture' || {
    # fixture form also prints pass equal answer
    true
  }
  echo "$out" | grep -qF 'pass equal answer' || {
    echo "FAIL vm_expect_pass (banner)"; fail=1; return 0; }
  # Three pass lines (equal literal, contains, equal fixture)
  local n
  n="$(echo "$out" | grep -c '\[expect\] pass' || true)"
  if [[ "$n" -lt 3 ]]; then
    echo "FAIL vm_expect_pass (want ≥3 pass lines, got $n)"
    echo "$out" | head -40
    fail=1
    return 0
  fi
  echo "PASS vm_expect_pass"
}
vm_ok

vm_fail() {
  local out rc=0
  set +e
  out="$(./spark --dry-run examples/expect_fail.spark 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL vm_expect_fail (expected non-zero)"
    echo "$out" | head -30
    fail=1
    return 0
  fi
  echo "$out" | grep -q 'got "Ada Lovelace" want "Grace Hopper"' || {
    echo "FAIL vm_expect_fail (reason)"; fail=1; return 0; }
  echo "PASS vm_expect_fail"
}
vm_fail

vm_miss_fixture() {
  local out rc=0
  set +e
  out="$(./spark --dry-run examples/expect_miss_fixture.spark 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL vm_expect_miss_fixture (expected non-zero)"
    fail=1
    return 0
  fi
  echo "$out" | grep -q 'fixture missing' || {
    echo "FAIL vm_expect_miss_fixture (reason)"; fail=1; return 0; }
  echo "PASS vm_expect_miss_fixture"
}
vm_miss_fixture

# --- flagship train → status → expect ---------------------------------
vm_train_eval() {
  local out n
  if ! out="$(./spark --dry-run examples/train_eval.spark 2>&1)"; then
    echo "FAIL vm_train_eval (exit $?)"
    echo "$out" | head -40
    fail=1
    return 0
  fi
  n="$(echo "$out" | grep -c '\[expect\] pass' || true)"
  if [[ "$n" -lt 2 ]]; then
    echo "FAIL vm_train_eval (want ≥2 pass lines, got $n)"
    echo "$out" | head -40
    fail=1
    return 0
  fi
  echo "$out" | grep -qF 'pass contains job' || {
    echo "FAIL vm_train_eval (job fixture)"; fail=1; return 0; }
  echo "$out" | grep -qF 'pass contains status' || {
    echo "FAIL vm_train_eval (status fixture)"; fail=1; return 0; }
  echo "PASS vm_train_eval"
}
vm_train_eval

vm_train_eval_fail() {
  local out rc=0
  set +e
  out="$(./spark --dry-run examples/train_eval_fail.spark 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL vm_train_eval_fail (expected non-zero)"
    echo "$out" | head -40
    fail=1
    return 0
  fi
  echo "$out" | grep -q 'state":"failed' || {
    echo "FAIL vm_train_eval_fail (reason)"
    echo "$out" | head -40
    fail=1
    return 0
  }
  echo "PASS vm_train_eval_fail"
}
vm_train_eval_fail

if [[ "$fail" -ne 0 ]]; then
  echo "test-expect FAIL"
  exit 1
fi
echo "test-expect OK (dry)"
exit 0
