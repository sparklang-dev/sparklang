#!/usr/bin/env bash
# After engine parse: <script> text → phase-1 engine_js_eval.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
make -s spark

fail=0

rm -f out/engine/js_result.txt out/engine/js_console.txt

./spark --dry-run examples/engine_parse.spark >/tmp/spark-parse-js.out
grep -qx '2' out/engine/js_result.txt && echo "PASS script_dom_hello_1+1" || {
  echo "FAIL script_dom_hello got: $(cat out/engine/js_result.txt 2>/dev/null)"
  fail=1
}

cat > /tmp/spark-parse-log.spark <<'EOF'
engine parse "engine/fixtures/script_log.html" -> dom
EOF
./spark --dry-run /tmp/spark-parse-log.spark >/dev/null
printf '2\n' > /tmp/spark-script-log-want.txt
cmp -s out/engine/js_console.txt /tmp/spark-script-log-want.txt && \
  echo "PASS script_dom_console.log" || {
  echo "FAIL script_dom_console got: $(od -c out/engine/js_console.txt | head -3)"
  fail=1
}

# Empty / no-script HTML must still parse (no eval fail)
cat > /tmp/spark-no-script.html <<'EOF'
<html><body><p>no script</p></body></html>
EOF
cat > /tmp/spark-parse-noscript.spark <<'EOF'
engine parse "/tmp/spark-no-script.html" -> dom
EOF
./spark --dry-run /tmp/spark-parse-noscript.spark >/dev/null && \
  echo "PASS script_dom_no_script" || {
  echo "FAIL script_dom_no_script"
  fail=1
}

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "engine JS <script> DOM hook OK"
