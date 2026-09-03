#!/usr/bin/env bash
# Every stdlib `extract` snippet the website publishes must be
# copy-paste runnable.
#
# The source of truth here is the generated catalog
# (website/data/function-catalog.json), not lib/*.spark, because the
# catalog is what a visitor actually copies. Testing the published bytes
# also catches generator regressions -- truncation before a closing
# brace, or lost indentation -- that reading the lib files would miss.
#
# Each snippet is run through the real GAS VM. Nothing is simulated.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

CATALOG="website/data/function-catalog.json"

[[ -x ./spark ]] || { echo "FAIL: ./spark not built (make spark)"; exit 1; }
# Catalog snippets may chain extract → expect (lib-expect-after-extract).
# Missing companion used to look like an expect bind failure.
[[ -x ./spark-expect ]] || {
  echo "FAIL: ./spark-expect not built (make spark-expect)"
  exit 1
}
[[ -f "$CATALOG" ]] || { echo "FAIL: missing $CATALOG"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Write one .spark per published snippet that contains an extract.
python3 - "$CATALOG" "$tmp" <<'PY'
import json
import pathlib
import re
import sys

catalog, outdir = sys.argv[1], pathlib.Path(sys.argv[2])
entries = json.loads(pathlib.Path(catalog).read_text())["entries"]
n = 0
for e in entries:
    syntax = e.get("syntax") or ""
    if not re.search(r"(^|\s)extract\s", syntax):
        continue
    ident = re.sub(r"[^A-Za-z0-9_-]", "_", e.get("id") or f"entry{n}")
    (outdir / f"{ident}.spark").write_text(
        "model fast\n\n" + syntax.rstrip() + "\n"
    )
    n += 1
if n == 0:
    sys.exit("no extract snippets in catalog")
PY

count=0
fail=0
for prog in "$tmp"/*.spark; do
  [[ -e "$prog" ]] || break
  count=$((count + 1))
  id="$(basename "$prog" .spark)"
  set +e
  # `let` in the GAS scaffold pads its dump with NULs (see the note in
  # selfhost/fixtures/extract_dry.spark). Strip them so command
  # substitution stays quiet; it does not affect the checks below.
  out="$(./spark --dry-run "$prog" 2>&1 | tr -d '\000')"
  rc=${PIPESTATUS[0]}
  set -e
  if [[ $rc -ne 0 ]]; then
    echo "FAIL $id: exit $rc"
    printf '%s\n' "$out" | sed 's/^/    /' | head -6
    fail=1
    continue
  fi
  # A clean exit is not enough: the snippet must actually produce the
  # extract line, or a silently-skipped statement would pass.
  if ! printf '%s\n' "$out" | grep -q '^\[extract\] '; then
    echo "FAIL $id: no [extract] output"
    printf '%s\n' "$out" | sed 's/^/    /' | head -6
    fail=1
    continue
  fi
  echo "PASS $id"
done

if [[ $count -eq 0 ]]; then
  echo "FAIL: no extract snippets found in $CATALOG"
  exit 1
fi
if [[ $fail -ne 0 ]]; then
  echo "test-extract-lib FAILED ($count published snippets)"
  exit 1
fi
echo "test-extract-lib OK ($count published snippets)"
