#!/usr/bin/env bash
# Engine B JS phase-1 — 1+1, string concat, unary -, var num, console.log.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
make -s spark

fail=0
run() {
  local name="$1" needle="$2"
  shift 2
  out="$(./spark --dry-run "$@" 2>&1)" || {
    echo "FAIL $name: non-zero"
    echo "$out" | head -20
    fail=1
    return
  }
  if echo "$out" | grep -qE "$needle"; then
    echo "PASS $name"
  else
    echo "FAIL $name: missing /$needle/"
    echo "$out" | head -30
    fail=1
  fi
}

# Expect non-zero + loud syntax error (unknown / unsupported)
run_fail() {
  local name="$1" needle="$2"
  shift 2
  set +e
  out="$(./spark --dry-run "$@" 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL $name: expected non-zero"
    echo "$out" | head -20
    fail=1
    return
  fi
  if echo "$out" | grep -qE "$needle"; then
    echo "PASS $name"
  else
    echo "FAIL $name: missing /$needle/ (rc=$rc)"
    echo "$out" | head -30
    fail=1
  fi
}

run js_add '→ 2' examples/js_phase1.spark
run js_cat '→ ab' examples/js_phase1.spark
run js_selftest 'selftest PASS' examples/js_phase1.spark
run js_browser_surface 'selftest PASS' browser/engine/js.spark

test -f out/engine/js_result.txt || {
  echo "FAIL js_result artifact"
  fail=1
}
grep -qx '2' out/engine/js_result.txt 2>/dev/null || \
  grep -q . out/engine/js_result.txt

# Re-run concat-only to check artifact
./spark --dry-run - <<'EOF' >/dev/null 2>&1 || true
EOF
# Direct eval via spark file
cat > /tmp/spark-js-cat.spark <<'EOF'
js eval "'a'+'b'" -> cat
EOF
./spark --dry-run /tmp/spark-js-cat.spark >/dev/null
grep -qx 'ab' out/engine/js_result.txt && echo "PASS js_result_ab" || {
  echo "FAIL js_result_ab got: $(cat out/engine/js_result.txt 2>/dev/null)"
  fail=1
}

cat > /tmp/spark-js-add.spark <<'EOF'
js eval "1+1" -> sum
EOF
./spark --dry-run /tmp/spark-js-add.spark >/dev/null
grep -qx '2' out/engine/js_result.txt && echo "PASS js_result_2" || {
  echo "FAIL js_result_2 got: $(cat out/engine/js_result.txt 2>/dev/null)"
  fail=1
}

cat > /tmp/spark-js-neg.spark <<'EOF'
js eval "-1" -> neg
EOF
./spark --dry-run /tmp/spark-js-neg.spark >/dev/null
grep -qx -- '-1' out/engine/js_result.txt && echo "PASS js_unary_minus" || {
  echo "FAIL js_unary_minus got: $(cat out/engine/js_result.txt 2>/dev/null)"
  fail=1
}

cat > /tmp/spark-js-negadd.spark <<'EOF'
js eval "-1+3" -> n
EOF
./spark --dry-run /tmp/spark-js-negadd.spark >/dev/null
grep -qx '2' out/engine/js_result.txt && echo "PASS js_unary_plus_chain" || {
  echo "FAIL js_unary_plus_chain got: $(cat out/engine/js_result.txt 2>/dev/null)"
  fail=1
}

cat > /tmp/spark-js-var.spark <<'EOF'
js eval "var x = 1; x+2" -> v
EOF
./spark --dry-run /tmp/spark-js-var.spark >/dev/null
grep -qx '3' out/engine/js_result.txt && echo "PASS js_var_num" || {
  echo "FAIL js_var_num got: $(cat out/engine/js_result.txt 2>/dev/null)"
  fail=1
}

cat > /tmp/spark-js-var-alone.spark <<'EOF'
js eval "var x = 7" -> v
EOF
./spark --dry-run /tmp/spark-js-var-alone.spark >/dev/null
grep -qx '7' out/engine/js_result.txt && echo "PASS js_var_assign_result" || {
  echo "FAIL js_var_assign_result got: $(cat out/engine/js_result.txt 2>/dev/null)"
  fail=1
}

cat > /tmp/spark-js-log.spark <<'EOF'
js run "console.log(1+1);console.log('a'+'b')" -> log
EOF
./spark --dry-run /tmp/spark-js-log.spark >/dev/null
printf '2\nab\n' > /tmp/spark-js-log-want.txt
cmp -s out/engine/js_console.txt /tmp/spark-js-log-want.txt && \
  echo "PASS js_console_buf" || {
  echo "FAIL js_console_buf got: $(od -c out/engine/js_console.txt | head -3)"
  fail=1
}

# Binary minus is NOT phase-1 — fail loud
cat > /tmp/spark-js-binminus.spark <<'EOF'
js eval "1-1" -> bad
EOF
run_fail js_binary_minus_loud 'js phase-1 syntax' /tmp/spark-js-binminus.spark

# Unary minus on string — fail loud
cat > /tmp/spark-js-negstr.spark <<'EOF'
js eval "-'a'" -> bad
EOF
run_fail js_unary_str_loud 'js phase-1 syntax' /tmp/spark-js-negstr.spark

# var string assign — fail loud (numbers only)
cat > /tmp/spark-js-varstr.spark <<'EOF'
js eval "var x = 'a'" -> bad
EOF
run_fail js_var_str_loud 'js phase-1 syntax' /tmp/spark-js-varstr.spark

# undeclared ident — fail loud
cat > /tmp/spark-js-undecl.spark <<'EOF'
js eval "x" -> bad
EOF
run_fail js_undecl_loud 'js phase-1 syntax' /tmp/spark-js-undecl.spark

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "engine JS phase-1 OK"
