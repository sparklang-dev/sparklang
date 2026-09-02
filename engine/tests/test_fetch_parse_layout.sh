#!/usr/bin/env bash
# fetch→parse→css→layout e2e on table_demo.html (layout.table proof).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
make -s spark

out="$(./spark --dry-run examples/engine_fetch_parse_layout.spark 2>&1)"
echo "$out" | grep -qE '"op":"engine.fetch"'
echo "$out" | grep -qE '"op":"engine.parse"'
echo "$out" | grep -qE '"tag_counts".*"table":1'
echo "$out" | grep -qE '"op":"engine.layout"'
echo "$out" | grep -qE '"op":"layout.table"'
echo "$out" | grep -qE '"border_cells":[1-9]'
cell0=$(echo "$out" | grep -oE '"cell0_x":[0-9]+' | head -1 | cut -d: -f2)
cell1=$(echo "$out" | grep -oE '"cell1_x":[0-9]+' | head -1 | cut -d: -f2)
test -n "$cell0" && test -n "$cell1"
test "$cell1" -gt "$cell0"
test -f out/engine/body.bin
test -f out/browser/engine/dom.json
test -f out/browser/engine/css.json
grep -q '"table":1' out/browser/engine/dom.json
echo "PASS engine-fetch-parse-layout"
