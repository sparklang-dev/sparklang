#!/usr/bin/env bash
# Offline gate: ./spark --embed handshake + Python host embed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
fail=0

if [[ ! -x ./spark ]]; then
  echo "Building spark…"
  make -s spark
fi

pass() { echo "PASS $1"; }
fail_one() {
  echo "FAIL $1 — $2"
  fail=1
}

# --- CLI handshake ----------------------------------------------------
hs="$(./spark --embed 2>&1)" || {
  fail_one embed_cli "spark --embed exited non-zero"
  hs=""
}
if echo "$hs" | grep -q '"spark_embed":true' \
  && echo "$hs" | grep -q '"api":"python"' \
  && echo "$hs" | grep -q 'sparklang'; then
  pass embed_cli_handshake
else
  fail_one embed_cli_handshake "unexpected JSON: $hs"
fi
if echo "$hs" | grep -q '"api":"stub"'; then
  fail_one embed_not_stub "still advertising stub API"
fi

export PYTHONPATH="$ROOT/python${PYTHONPATH:+:$PYTHONPATH}"

# --- Python import + path dry-run -------------------------------------
set +e
py_out="$(python3 - <<'PY' 2>&1
from sparklang import run

r = run("examples/hello.spark")
assert r.ok, (r.returncode, r.stderr)
assert r.mode == "dry-run"
assert len(r.stdout) > 0
print("OK path", r.returncode, len(r.stdout))
PY
)"
py_rc=$?
set -e
if [[ "$py_rc" -eq 0 ]] && echo "$py_out" | grep -q '^OK path'; then
  pass py_path_dry
else
  fail_one py_path_dry "rc=$py_rc out=$py_out"
fi

# --- Inline source string ---------------------------------------------
set +e
py_src="$(python3 - <<'PY' 2>&1
from sparklang import run

src = 'print "host-embed-marker"\n'
r = run(src)
assert r.ok, (r.returncode, r.stderr)
assert "host-embed-marker" in r.stdout
print("OK src", r.returncode)
PY
)"
py_rc=$?
set -e
if [[ "$py_rc" -eq 0 ]] && echo "$py_src" | grep -q '^OK src'; then
  pass py_inline_source
else
  fail_one py_inline_source "rc=$py_rc out=$py_src"
fi

# --- Fail loud: missing file ------------------------------------------
set +e
py_miss="$(python3 - <<'PY' 2>&1
from sparklang import run

try:
    run("examples/does-not-exist-host-embed.spark")
except FileNotFoundError as e:
    print("OK miss", e)
else:
    raise SystemExit("expected FileNotFoundError")
PY
)"
py_rc=$?
set -e
if [[ "$py_rc" -eq 0 ]] && echo "$py_miss" | grep -q '^OK miss'; then
  pass py_missing_file
else
  fail_one py_missing_file "rc=$py_rc out=$py_miss"
fi

# --- Fail loud: dry refuse non-allowlisted shell ----------------------
set +e
py_ref="$(python3 - <<'PY' 2>&1
from sparklang import run

bad = 'shell "rm -rf /" -> out\nprint out\n'
r = run(bad)
assert not r.ok, "dry-run must refuse non-allowlisted shell"
assert r.returncode != 0
print("OK refuse", r.returncode)
PY
)"
py_rc=$?
set -e
if [[ "$py_rc" -eq 0 ]] && echo "$py_ref" | grep -q '^OK refuse'; then
  pass py_shell_refuse
else
  fail_one py_shell_refuse "rc=$py_rc out=$py_ref"
fi

# --- Example script ---------------------------------------------------
set +e
PYTHONPATH="$ROOT/python" python3 \
  examples/python/host_embed.py >/dev/null 2>&1
ex_rc=$?
set -e
if [[ "$ex_rc" -eq 0 ]]; then
  pass example_host_embed_py
else
  fail_one example_host_embed_py "rc=$ex_rc"
fi

# --- Module CLI -------------------------------------------------------
set +e
mod_out="$(PYTHONPATH="$ROOT/python" python3 -m sparklang \
  examples/hello.spark 2>&1)"
mod_rc=$?
set -e
if [[ "$mod_rc" -eq 0 ]] && [[ -n "$mod_out" ]]; then
  pass mod_cli
else
  fail_one mod_cli "rc=$mod_rc out=$mod_out"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "host-embed gate FAILED"
  exit 1
fi
echo "test-host-embed OK"
exit 0
