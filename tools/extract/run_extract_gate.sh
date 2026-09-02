#!/usr/bin/env bash
# Offline dry gate for spark-extract (typed extract + schema validation).
#
# Every case here is offline: the fixture on disk is the only source of
# field values. The negative cases assert a non-zero exit, because a
# validator that prints a complaint and exits 0 has not validated
# anything.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
fail=0

if [[ ! -x ./spark-extract ]]; then
  echo "Building spark-extract…"
  make -s spark-extract
fi
if [[ ! -x ./spark ]]; then
  echo "Building spark…"
  make -s spark
fi

FX=examples/fixtures/extract

# Expect success, and expect a substring in the output.
expect_ok() {
  local name="$1" schema="$2" fixture="$3" want="$4"
  local out
  if ! out="$(./spark-extract --dry --schema "$schema" \
      --fixture "$fixture" 2>&1)"; then
    echo "FAIL $name (expected exit 0, got $?)"
    echo "$out" | head -20
    fail=1
    return 0
  fi
  if ! echo "$out" | grep -qF "$want"; then
    echo "FAIL $name (missing: $want)"
    echo "$out" | head -20
    fail=1
    return 0
  fi
  echo "PASS $name"
}

# Expect a non-zero exit, and expect the reason to say why.
expect_fail() {
  local name="$1" schema="$2" fixture="$3" want="$4"
  local out rc=0
  set +e
  out="$(./spark-extract --dry --schema "$schema" \
    --fixture "$fixture" 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL $name (expected non-zero, got 0)"
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

PERSON='extract Person { name: string, age: int }'

# --- validation passes ------------------------------------------------
expect_ok  valid_required \
  "$PERSON" "$FX/person.json" '"name":"Ada Lovelace"'
expect_ok  valid_extra_field_allowed \
  "$PERSON" "$FX/nested.json" '"name":"Ada Lovelace"'
expect_ok  valid_optional_absent \
  'extract Person { name: string, age: int, email?: string }' \
  "$FX/person.json" 'dry ok'
expect_ok  valid_float_accepts_int \
  'extract M { score: float }' "$FX/metrics.json" 'dry ok'
expect_ok  valid_float_and_bool \
  'extract M { ratio: float, passed: bool, label: string }' \
  "$FX/metrics.json" 'dry ok'

# --- validation fails -------------------------------------------------
expect_fail missing_required_field \
  "$PERSON" "$FX/person_missing_age.json" 'missing required field age'
expect_fail wrong_type_int_vs_string \
  "$PERSON" "$FX/person_bad_type.json" \
  'field age expected int, fixture has string'
expect_fail optional_present_wrong_type \
  'extract Person { name: string, email?: string }' \
  "$FX/optional_bad.json" 'field email expected string, fixture has int'
expect_fail bool_not_satisfied_by_int \
  'extract M { score: bool }' "$FX/metrics.json" \
  'field score expected bool, fixture has int'
expect_fail int_not_satisfied_by_float \
  'extract M { ratio: int }' "$FX/metrics.json" \
  'field ratio expected int, fixture has float'

# A key that exists only inside a nested object must not satisfy a
# top-level required field.
expect_fail nested_key_does_not_count \
  "$PERSON" "$FX/nested_only.json" 'missing required field age'

# --- schema errors ----------------------------------------------------
expect_fail unknown_type \
  'extract Person { name: strng }' "$FX/person.json" \
  'unknown type "strng"'
expect_fail no_schema_block \
  'extract Person from "x"' "$FX/person.json" 'schema block'
expect_fail empty_schema \
  'extract Person { }' "$FX/person.json" 'declares no fields'
expect_fail missing_type \
  'extract Person { name }' "$FX/person.json" 'needs ": type"'

# --- fixture errors ---------------------------------------------------
expect_fail fixture_file_missing \
  "$PERSON" "$FX/does_not_exist.json" 'fixture missing'

no_fixture_clause() {
  local out rc=0
  set +e
  out="$(./spark-extract --dry --schema "$PERSON" 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL no_fixture_clause (expected non-zero)"
    fail=1
    return 0
  fi
  if ! echo "$out" | grep -qF 'requires fixture'; then
    echo "FAIL no_fixture_clause (wrong reason)"
    echo "$out" | head -20
    fail=1
    return 0
  fi
  echo "PASS no_fixture_clause"
}
no_fixture_clause

# Live is not implemented; it must say so, not silently read the fixture.
live_refused() {
  local out rc=0
  set +e
  out="$(./spark-extract --live --schema "$PERSON" \
    --fixture "$FX/person.json" 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL live_refused (expected non-zero)"
    fail=1
    return 0
  fi
  if ! echo "$out" | grep -qF 'not implemented'; then
    echo "FAIL live_refused (wrong reason)"
    echo "$out" | head -20
    fail=1
    return 0
  fi
  echo "PASS live_refused"
}
live_refused

# --- through the assembly VM ------------------------------------------
# The multi-line schema block, the fixture read, and the -> binding all
# have to work in the interpreter, not just in the companion.
vm_ok() {
  local out
  if ! out="$(./spark --dry-run examples/extract_person.spark 2>&1)"; then
    echo "FAIL vm_extract_ok (exit $?)"
    echo "$out" | head -30
    fail=1
    return 0
  fi
  echo "$out" | grep -q '\[extract\]' || {
    echo "FAIL vm_extract_ok (no [extract] banner)"; fail=1; return 0; }
  echo "$out" | grep -q 'dry schema=Person fields=3' || {
    echo "FAIL vm_extract_ok (schema line)"; fail=1; return 0; }
  echo "$out" | grep -q '\[print\] {"name":"Ada Lovelace"' || {
    echo "FAIL vm_extract_ok (binding)"; fail=1; return 0; }
  echo "PASS vm_extract_ok"
}
vm_ok

vm_fail() {
  local out rc=0
  set +e
  out="$(./spark --dry-run examples/extract_bad.spark 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL vm_extract_bad (expected non-zero)"
    echo "$out" | head -30
    fail=1
    return 0
  fi
  # A failed extract must not bind or print a result.
  if echo "$out" | grep -q '\[print\]'; then
    echo "FAIL vm_extract_bad (printed a result after failing)"
    fail=1
    return 0
  fi
  echo "$out" | grep -q 'expected int, fixture has string' || {
    echo "FAIL vm_extract_bad (reason)"; fail=1; return 0; }
  echo "PASS vm_extract_bad"
}
vm_fail

if [[ "$fail" -ne 0 ]]; then
  echo "test-extract FAIL"
  exit 1
fi
echo "test-extract OK (dry)"
exit 0
