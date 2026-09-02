#!/usr/bin/env bash
# Box-count + table-row side-by-side proof for engine B layout.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
make -s spark-engine-layout-test
out="$(./spark-engine-layout-test)"
echo "$out"
echo "$out" | grep -qE '"box_count":8'
echo "$out" | grep -qE '"op":"layout"'
echo "$out" | grep -qE '"ok":true'
echo "$out" | grep -qE '"op":"layout.table"'
cell0=$(echo "$out" | grep -oE '"cell0_x":[0-9]+' | head -1 | cut -d: -f2)
cell1=$(echo "$out" | grep -oE '"cell1_x":[0-9]+' | head -1 | cut -d: -f2)
test -n "$cell0" && test -n "$cell1"
test "$cell1" -gt "$cell0"
echo "$out" | grep -qE '"border_cells":[1-9]'
echo "PASS engine-layout-boxes (+ table row + borders)"
