#!/usr/bin/env bash
# Table fixture pipeline + cell-border + in-cell text paint proof.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
make -s spark spark-engine-layout-test

layout_out="$(./spark-engine-layout-test)"
echo "$layout_out" | grep -qE '"op":"layout.table"'
echo "$layout_out" | grep -qE '"border_cells":[1-9]'
echo "$layout_out" | grep -qE '"cell_text":[1-9]'
# Glyphs must share cell_y (inside viewport — not painted at y=0 only).
echo "$layout_out" | grep -qE '"cell_y":[0-9]+'
cell_y="$(echo "$layout_out" | sed -n 's/.*"cell_y":\([0-9]*\).*/\1/p' | head -1)"
test -n "$cell_y"
test "$cell_y" -lt 480

./spark --dry-run examples/engine_pipeline_table.spark >/tmp/spark_pipeline_table.out 2>&1
grep -q '"op":"show"' /tmp/spark_pipeline_table.out
grep -qE '"cell_text":[1-9]' /tmp/spark_pipeline_table.out
test -f out/engine/pipeline.ppm
test -f out/browser/show.json
test -f out/browser/engine/css.json
grep -qE '"padding":4' out/browser/engine/css.json
grep -qE '"border_width":2' out/browser/engine/css.json
grep -qE '"color":"c80000"' out/browser/engine/css.json
grep -qE '"background_color":"00c800"' out/browser/engine/css.json
grep -qE '"width":320' out/browser/engine/css.json
grep -qE '"height":48' out/browser/engine/css.json
grep -q 'pipeline.ppm' out/browser/show.json
test "$(wc -c < out/engine/pipeline.ppm)" -gt 1000
# Dark cell glyphs + red #c80000 text + green #00c800 fills.
# Multi-px border: fixtures set border-width:2 → stroke #606060.
python3 - <<'PY'
from pathlib import Path
p = Path("out/engine/pipeline.ppm").read_bytes()
assert p.startswith(b"P6\n"), p[:16]
_, dims, _, body = p.split(b"\n", 3)
w, h = map(int, dims.split())
assert w == 640 and h == 480
dark = redish = greenish = gray = 0
for i in range(0, len(body), 3):
    r, g, b = body[i], body[i + 1], body[i + 2]
    if r < 40 and g < 40 and b < 40:
        dark += 1
    # #c80000 ink on fill — not a solid red rect
    if r >= 180 and g < 40 and b < 40:
        redish += 1
    # #00c800 background-color on td fills
    if r < 40 and g >= 180 and b < 40:
        greenish += 1
    # #606060 multi-px cell border stroke (2px > 1px baseline ~2928)
    if r == 0x60 and g == 0x60 and b == 0x60:
        gray += 1
assert dark >= 20, f"expected cell glyphs, dark={dark}"
assert redish >= 8, f"expected #c80000 text glyphs, redish={redish}"
assert greenish >= 40, (
    f"expected #00c800 fills, greenish={greenish}"
)
assert gray >= 5000, (
    f"expected 2px border stroke #606060, gray={gray}"
)
print(
    "PASS engine-pipeline-table cell_text dark=",
    dark,
    "redish=",
    redish,
    "greenish=",
    greenish,
    "gray606=",
    gray,
)
PY
echo "PASS engine-pipeline-table"
