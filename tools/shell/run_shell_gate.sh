#!/usr/bin/env bash
# Offline + live-allowlist gate for spark-shell / --allow-shell.
# Live exec is echo|true|false via execve — never system().
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
fail=0

if [[ ! -x ./spark-shell ]]; then
  echo "Building spark-shell…"
  make -s spark-shell
fi
if [[ ! -x ./spark ]]; then
  echo "Building spark…"
  make -s spark
fi

pass() { echo "PASS $1"; }
fail_one() {
  echo "FAIL $1 — $2"
  fail=1
}

# --- Companion dry (no exec) -----------------------------------------
set +e
dry_out="$(./spark-shell --dry -- echo hello 2>&1)"
dry_rc=$?
set -e
if [[ "$dry_rc" -eq 0 ]] \
  && echo "$dry_out" | grep -q '"mode":"dry-run"' \
  && echo "$dry_out" | grep -q 'fixture' \
  && echo "$dry_out" | grep -q hello; then
  pass companion_dry_echo
else
  fail_one companion_dry_echo "rc=$dry_rc out=$dry_out"
fi

# --- Companion live execve (echo) ------------------------------------
set +e
live_out="$(./spark-shell --live -- echo hello 2>&1)"
live_rc=$?
set -e
if [[ "$live_rc" -eq 0 ]] \
  && echo "$live_out" | grep -q '"mode":"live"' \
  && echo "$live_out" | grep -q hello \
  && echo "$live_out" | grep -q execve; then
  pass companion_live_echo
else
  fail_one companion_live_echo "rc=$live_rc out=$live_out"
fi

# --- Companion live true / false -------------------------------------
set +e
t_out="$(./spark-shell --live -- true 2>&1)"
t_rc=$?
set -e
if [[ "$t_rc" -eq 0 ]] && echo "$t_out" | grep -q '"ok":true'; then
  pass companion_live_true
else
  fail_one companion_live_true "rc=$t_rc out=$t_out"
fi

set +e
f_out="$(./spark-shell --live -- false 2>&1)"
f_rc=$?
set -e
if [[ "$f_rc" -eq 0 ]] && echo "$f_out" | grep -q '"ok":false'; then
  pass companion_live_false
else
  fail_one companion_live_false "rc=$f_rc out=$f_out"
fi

# --- Refuse: not on allowlist ----------------------------------------
set +e
rm_out="$(./spark-shell --live -- rm -rf / 2>&1)"
rm_rc=$?
set -e
if [[ "$rm_rc" -ne 0 ]] && echo "$rm_out" | grep -qi allowlist; then
  pass companion_refuse_rm
else
  fail_one companion_refuse_rm "rc=$rm_rc out=$rm_out"
fi

# --- Refuse: path / metacharacters -----------------------------------
set +e
path_out="$(./spark-shell --live -- /bin/echo hello 2>&1)"
path_rc=$?
set -e
if [[ "$path_rc" -ne 0 ]]; then
  pass companion_refuse_path
else
  fail_one companion_refuse_path "path exec was allowed: $path_out"
fi

set +e
meta_out="$(./spark-shell --live -- echo 'hello;id' 2>&1)"
meta_rc=$?
set -e
if [[ "$meta_rc" -ne 0 ]] && echo "$meta_out" | grep -qiE 'meta|refus'; then
  pass companion_refuse_meta
else
  fail_one companion_refuse_meta "rc=$meta_rc out=$meta_out"
fi

# --- Need exactly one of --dry/--live --------------------------------
set +e
both_out="$(./spark-shell --dry --live -- echo hello 2>&1)"
both_rc=$?
set -e
if [[ "$both_rc" -ne 0 ]]; then
  pass companion_refuse_both_modes
else
  fail_one companion_refuse_both_modes "accepted both flags"
fi

# --- GAS dry-run still fixtures (even with --allow-shell) ------------
set +e
gas_dry="$(./spark --dry-run --allow-shell \
  examples/shell_escape.spark 2>&1)"
gas_dry_rc=$?
set -e
if [[ "$gas_dry_rc" -eq 0 ]] \
  && echo "$gas_dry" | grep -q 'dry-run' \
  && echo "$gas_dry" | grep -q 'fixture' \
  && ! echo "$gas_dry" | grep -q execve; then
  pass gas_dry_no_exec
else
  fail_one gas_dry_no_exec "rc=$gas_dry_rc out=$gas_dry"
fi

# --- GAS live without --allow-shell refuses --------------------------
set +e
gas_nolive="$(./spark --live examples/shell_escape.spark 2>&1)"
gas_nolive_rc=$?
set -e
if [[ "$gas_nolive_rc" -ne 0 ]] \
  && echo "$gas_nolive" | grep -q -- '--allow-shell'; then
  pass gas_live_needs_flag
else
  fail_one gas_live_needs_flag "rc=$gas_nolive_rc out=$gas_nolive"
fi

# --- GAS live + --allow-shell execve path ----------------------------
set +e
gas_live="$(./spark --live --allow-shell \
  examples/shell_escape.spark 2>&1)"
gas_live_rc=$?
set -e
if [[ "$gas_live_rc" -eq 0 ]] \
  && echo "$gas_live" | grep -q '"mode":"live"' \
  && echo "$gas_live" | grep -q hello \
  && echo "$gas_live" | grep -q execve; then
  pass gas_live_allow_shell
else
  fail_one gas_live_allow_shell "rc=$gas_live_rc out=$gas_live"
fi

# --- GAS live + allow-shell still refuses rm -------------------------
set +e
gas_rm="$(./spark --live --allow-shell \
  examples/shell_refuse.spark 2>&1)"
gas_rm_rc=$?
set -e
if [[ "$gas_rm_rc" -ne 0 ]]; then
  pass gas_live_refuse_rm
else
  fail_one gas_live_refuse_rm "rm was allowed: $gas_rm"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "test-shell FAILED"
  exit 1
fi
echo "test-shell OK"
exit 0
