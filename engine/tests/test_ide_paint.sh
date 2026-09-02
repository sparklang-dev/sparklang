#!/usr/bin/env bash
# Spark IDE editor paint — non-empty PPM with gutter glyphs + cursor.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
make -s spark-ide-paint
rm -f out/ide/editor.ppm
./spark-ide-paint
PPM=out/ide/editor.ppm
test -f "$PPM" || { echo "FAIL ide-paint: missing $PPM"; exit 1; }
sz=$(wc -c < "$PPM")
test "$sz" -gt 100 || { echo "FAIL ide-paint: PPM too small ($sz)"; exit 1; }
head -c 2 "$PPM" | grep -q "P6" || { echo "FAIL ide-paint: not P6"; exit 1; }
python3 - "$PPM" <<'PY'
import sys
p = open(sys.argv[1], "rb").read()
assert p.startswith(b"P6\n"), p[:16]
a, b, c, body = p.split(b"\n", 3)
w, h = map(int, b.split())
assert c == b"255", c
assert w == 320 and h == 160, (w, h)
assert len(body) == w * h * 3, len(body)
# Must not be flat background — glyphs / cursor leave bright pixels
bright = 0
for j in range(0, len(body), 3):
    if body[j] > 100 or body[j + 1] > 100 or body[j + 2] > 100:
        bright += 1
assert bright > 50, f"too few bright pixels ({bright}) — no text?"
# Regions: status (top 16), gutter, text, AI panel (bottom 24)
gw = 40
status_h = 16
panel_y0 = h - 24
status = []
gutter = []
text = []
panel = []
for y in range(h):
    for x in range(w):
        i = (y * w + x) * 3
        pix = body[i : i + 3]
        if y < status_h:
            status.append(pix)
        elif y >= panel_y0:
            panel.append(pix)
        elif x < gw:
            gutter.append(pix)
        elif x >= 44:
            text.append(pix)
assert any(p != status[0] for p in status[1:]), "flat status strip"
assert any(p != gutter[0] for p in gutter[1:]), "flat gutter"
assert any(p != text[0] for p in text[1:]), "flat text"
assert any(p != panel[0] for p in panel[1:]), "flat AI panel"
# Status strip should have bright path glyphs
status_bright = sum(
    1 for p in status if p[0] > 60 or p[1] > 100 or p[2] > 100
)
assert status_bright > 20, f"status strip too dim ({status_bright})"
# AI strip should have bright cyan/teal glyphs
panel_bright = sum(
    1 for p in panel if p[0] > 60 or p[1] > 100 or p[2] > 100
)
assert panel_bright > 20, f"AI panel too dim ({panel_bright})"
print(
    "PASS ide-paint-ppm",
    "bytes=",
    len(p),
    "bright=",
    bright,
    "status_bright=",
    status_bright,
    "ai_panel_bright=",
    panel_bright,
)
PY
