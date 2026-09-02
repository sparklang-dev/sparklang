#!/usr/bin/env bash
# Engine B paint fixture — non-empty PPM with rects + glyphs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
make -s spark-engine-paint
rm -f out/engine/paint_fixture.ppm
./spark-engine-paint
PPM=out/engine/paint_fixture.ppm
test -f "$PPM" || { echo "FAIL paint: missing $PPM"; exit 1; }
# P6 header + binary payload must be non-trivial
sz=$(wc -c < "$PPM")
test "$sz" -gt 100 || { echo "FAIL paint: PPM too small ($sz)"; exit 1; }
head -c 2 "$PPM" | grep -q "P6" || { echo "FAIL paint: not P6"; exit 1; }
# Must contain non-white pixels (fixture draws colored rects)
python3 - "$PPM" <<'PY'
import sys
p = open(sys.argv[1], "rb").read()
assert p.startswith(b"P6\n"), p[:16]
a, b, c, body = p.split(b"\n", 3)
w, h = map(int, b.split())
assert c == b"255", c
assert w == 160 and h == 80, (w, h)
assert len(body) == w * h * 3, len(body)
ok = any(body[j : j + 3] != b"\xff\xff\xff" for j in range(0, len(body), 3))
assert ok, "all white — paint did not draw"
print("PASS engine-paint-ppm", "bytes=", len(p), "rgb=", len(body))
PY
