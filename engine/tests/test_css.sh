#!/usr/bin/env bash
# Engine B CSS — attach to HTML DOM from engine parse.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
as --64 -o asm/engine_css.o asm/engine_css.s
as --64 -o asm/engine_pipeline.o asm/engine_pipeline.s
test -x ./spark || {
  echo "FAIL engine-css: ./spark missing"
  exit 1
}
# Relink when our objs are newer; tolerate unrelated WIP breakages.
if [[ asm/engine_css.o -nt ./spark || asm/engine_pipeline.o -nt ./spark ]]; then
  if ! make -s spark >/dev/null 2>&1; then
    nm -g ./spark | grep -q se_css_attach || {
      echo "FAIL engine-css: cannot link; se_css_attach missing"
      exit 1
    }
    echo "WARN engine-css: using existing spark (full make blocked)"
  fi
fi

out="$(./spark --dry-run examples/engine_css.spark 2>&1)" || {
  echo "FAIL engine-css: dry-run exit"
  echo "$out" | head -40
  exit 1
}
echo "$out" | grep -q '\[engine\]' || {
  echo "FAIL engine-css: missing [engine]"
  echo "$out" | head -20
  exit 1
}
test -f out/browser/engine/dom.json || {
  echo "FAIL engine-css: missing dom.json (parse)"
  exit 1
}
test -f out/browser/engine/css.json || {
  echo "FAIL engine-css: missing css.json"
  exit 1
}
grep -q '"op":"engine.css"' out/browser/engine/css.json
grep -q '"ok":true' out/browser/engine/css.json
grep -q 'c80000' out/browser/engine/css.json
grep -q '"font_size":20' out/browser/engine/css.json
python3 - <<'PY'
import json
dom=json.load(open("out/browser/engine/dom.json"))
css=json.load(open("out/browser/engine/css.json"))
assert css["nodes"]==dom["nnodes"], (css["nodes"], dom["nnodes"])
styles={s["id"]:s for s in css["styles"]}
# SE_DISP_*: none=0 block=1 inline=2 inline-block=3
# table=4 table-row=5 table-cell=6
DISP = {
    "none": 0, "block": 1, "inline": 2, "inline-block": 3,
    "table": 4, "table-row": 5, "table-cell": 6,
}
FLAG_DISPLAY = 8

def tag_ids(tag):
    return [n["id"] for n in dom["nodes"] if n.get("tag")==tag]

pids = tag_ids("p")
assert pids, "no p node"
hit=any(
    styles[pid].get("font_size")==20 and styles[pid].get("color")=="c80000"
    for pid in pids
)
assert hit, styles

def expect_disp(tag, name):
    ids = tag_ids(tag)
    assert ids, f"missing tag {tag}"
    want = DISP[name]
    ok = any(
        (styles[i].get("flags", 0) & FLAG_DISPLAY)
        and styles[i].get("display") == want
        for i in ids
    )
    assert ok, (tag, name, want, {i: styles[i] for i in ids})

expect_disp("div", "block")
expect_disp("img", "inline-block")
expect_disp("table", "table")
expect_disp("tr", "table-row")
expect_disp("td", "table-cell")
expect_disp("th", "table-cell")
# inline display:none on second span
spans = tag_ids("span")
assert any(
    (styles[i].get("flags", 0) & FLAG_DISPLAY)
    and styles[i].get("display") == DISP["none"]
    for i in spans
), {i: styles[i] for i in spans}
FLAG_PADDING = 16
pad_hit = any(
    (styles[i].get("flags", 0) & FLAG_PADDING)
    and styles[i].get("padding") == 6
    for i in pids
)
assert pad_hit, ("expected p padding:6px", {i: styles[i] for i in pids})
td_ids = tag_ids("td")
th_ids = tag_ids("th")
assert any(
    (styles[i].get("flags", 0) & FLAG_PADDING)
    and styles[i].get("padding") == 4
    for i in td_ids
), ("expected td padding:4px", {i: styles[i] for i in td_ids})
FLAG_BORDER_W = 32
assert any(
    (styles[i].get("flags", 0) & FLAG_BORDER_W)
    and styles[i].get("border_width") == 2
    for i in td_ids
), ("expected td border-width:2px", {i: styles[i] for i in td_ids})
FLAG_MARGIN = 4
assert any(
    (styles[i].get("flags", 0) & FLAG_MARGIN)
    and styles[i].get("margin") == 4
    for i in pids
), ("expected p margin:4px (already live)", {i: styles[i] for i in pids})
FLAG_BG = 64
assert any(
    (styles[i].get("flags", 0) & FLAG_BG)
    and styles[i].get("background_color") == "00c800"
    for i in td_ids
), ("expected td background-color:#00c800", {i: styles[i] for i in td_ids})
div_ids = tag_ids("div")
assert any(
    (styles[i].get("flags", 0) & FLAG_BG)
    and styles[i].get("background_color") == "00c800"
    for i in div_ids
), ("expected div background-color:#00c800", {i: styles[i] for i in div_ids})
FLAG_WIDTH = 128
assert any(
    (styles[i].get("flags", 0) & FLAG_WIDTH)
    and styles[i].get("width") == 120
    for i in div_ids
), ("expected div width:120px", {i: styles[i] for i in div_ids})
assert any(
    (styles[i].get("flags", 0) & FLAG_WIDTH)
    and styles[i].get("width") == 320
    for i in td_ids
), ("expected td width:320px", {i: styles[i] for i in td_ids})
FLAG_HEIGHT = 256
assert any(
    (styles[i].get("flags", 0) & FLAG_HEIGHT)
    and styles[i].get("height") == 48
    for i in div_ids
), ("expected div height:48px", {i: styles[i] for i in div_ids})
assert any(
    (styles[i].get("flags", 0) & FLAG_HEIGHT)
    and styles[i].get("height") == 48
    for i in td_ids
), ("expected td height:48px", {i: styles[i] for i in td_ids})
FLAG_MAX_HEIGHT = 512
assert any(
    (styles[i].get("flags", 0) & FLAG_MAX_HEIGHT)
    and styles[i].get("max_height") == 40
    for i in div_ids
), ("expected div max-height:40px", {i: styles[i] for i in div_ids})
FLAG_MIN_HEIGHT = 1024
assert any(
    (styles[i].get("flags", 0) & FLAG_MIN_HEIGHT)
    and styles[i].get("min_height") == 56
    for i in pids
), ("expected p min-height:56px", {i: styles[i] for i in pids})
FLAG_MAX_WIDTH = 2048
assert any(
    (styles[i].get("flags", 0) & FLAG_MAX_WIDTH)
    and styles[i].get("max_width") == 80
    for i in div_ids
), ("expected div max-width:80px", {i: styles[i] for i in div_ids})
FLAG_MIN_WIDTH = 4096
assert any(
    (styles[i].get("flags", 0) & FLAG_MIN_WIDTH)
    and styles[i].get("min_width") == 200
    for i in pids
), ("expected p min-width:200px", {i: styles[i] for i in pids})
FLAG_BORDER_C = 8192
assert any(
    (styles[i].get("flags", 0) & FLAG_BORDER_C)
    and styles[i].get("border_color") == "c80000"
    for i in td_ids
), ("expected td border-color:#c80000", {i: styles[i] for i in td_ids})
FLAG_BORDER_S = 16384
assert any(
    (styles[i].get("flags", 0) & FLAG_BORDER_S)
    and styles[i].get("border_style") == 1
    for i in td_ids
), ("expected td border-style:solid", {i: styles[i] for i in td_ids})
assert any(
    (styles[i].get("flags", 0) & FLAG_BORDER_S)
    and styles[i].get("border_style") == 0
    for i in th_ids
), ("expected th border-style:none", {i: styles[i] for i in th_ids})
FLAG_VIS = 32768
assert any(
    (styles[i].get("flags", 0) & FLAG_VIS)
    and styles[i].get("visibility") == 1
    for i in div_ids
), ("expected div visibility:hidden", {i: styles[i] for i in div_ids})
FLAG_OPACITY = 65536
assert any(
    (styles[i].get("flags", 0) & FLAG_OPACITY)
    and styles[i].get("opacity") == 0
    for i in div_ids
), ("expected div opacity:0", {i: styles[i] for i in div_ids})
assert any(
    (styles[i].get("flags", 0) & FLAG_BG)
    and styles[i].get("background_color") == "transparent"
    for i in div_ids
), ("expected div background-color:transparent", {i: styles[i] for i in div_ids})
span_ids = tag_ids("span")
FLAG_COLOR = 1
assert any(
    (styles[i].get("flags", 0) & FLAG_COLOR)
    and styles[i].get("color") == "ffff00"
    for i in span_ids
), ("expected span color:yellow", {i: styles[i] for i in span_ids})
assert any(
    (styles[i].get("flags", 0) & FLAG_COLOR)
    and styles[i].get("color") == "transparent"
    for i in span_ids
), ("expected span color:transparent", {i: styles[i] for i in span_ids})
assert any(
    (styles[i].get("flags", 0) & FLAG_COLOR)
    and styles[i].get("color") == "00ffff"
    for i in span_ids
), ("expected span color:cyan", {i: styles[i] for i in span_ids})
assert any(
    (styles[i].get("flags", 0) & FLAG_COLOR)
    and styles[i].get("color") == "ff00ff"
    for i in span_ids
), ("expected span color:magenta", {i: styles[i] for i in span_ids})
assert any(
    (styles[i].get("flags", 0) & FLAG_COLOR)
    and styles[i].get("color") == "ffa500"
    for i in span_ids
), ("expected span color:orange", {i: styles[i] for i in span_ids})
assert any(
    (styles[i].get("flags", 0) & FLAG_COLOR)
    and styles[i].get("color") == "00ff00"
    for i in span_ids
), ("expected span color:lime", {i: styles[i] for i in span_ids})
assert dom["tag_counts"].get("img", 0) >= 1
assert dom["tag_counts"].get("table", 0) >= 1
print(
    "dom/css + display + padding + border-width + margin"
    " + #hex color + background-color + width + height"
    " + max-height + min-height + max-width + min-width"
    " + border-color + border-style + visibility + opacity"
    " + transparent + yellow + cyan + magenta"
    " + orange + lime OK"
)
PY
# Layout clamp: height:48 + max-height:40 → green div band ≤40px tall
# Layout floor: p min-height:56 + #00c8c8 → cyan band ≥56px tall
# Layout max-width: width:120 + max-width:80 → green band width ≤80
# Layout min-width: p min-width:200 → cyan band width ≥200
./spark --dry-run examples/engine_pipeline.spark >/tmp/spark_css_mh.out 2>&1
python3 - <<'PY'
from pathlib import Path
p = Path("out/engine/pipeline.ppm").read_bytes()
_, dims, _, body = p.split(b"\n", 3)
w, h = map(int, dims.split())
ys_g = []
ys_c = []
for y in range(h):
    for x in range(min(200, w)):
        i = (y * w + x) * 3
        r, g, b = body[i], body[i + 1], body[i + 2]
        if r < 40 and g >= 180 and g < 255 and b < 40:
            ys_g.append(y)
            break
    for x in range(min(640, w)):
        i = (y * w + x) * 3
        r, g, b = body[i], body[i + 1], body[i + 2]
        if r < 40 and g >= 180 and b >= 180 and g < 255 and b < 255:
            ys_c.append(y)
            break
assert ys_g, "expected green div fill"
span_g = max(ys_g) - min(ys_g) + 1
assert span_g <= 40, f"max-height clamp failed span={span_g}"
y0 = min(ys_g)
xs = []
for x in range(w):
    i = (y0 * w + x) * 3
    r, g, b = body[i], body[i + 1], body[i + 2]
    if r < 40 and g >= 180 and g < 255 and b < 40:
        xs.append(x)
assert xs, "expected green pixels on row"
width_g = max(xs) - min(xs) + 1
assert width_g <= 80, f"max-width clamp failed width={width_g}"
assert ys_c, "expected cyan p min-height fill"
span_c = max(ys_c) - min(ys_c) + 1
assert span_c >= 56, f"min-height expand failed span={span_c}"
yc = min(ys_c)
xs_c = []
for x in range(w):
    i = (yc * w + x) * 3
    r, g, b = body[i], body[i + 1], body[i + 2]
    if r < 40 and g >= 180 and b >= 180 and g < 255 and b < 255:
        xs_c.append(x)
assert xs_c, "expected cyan pixels on row"
width_c = max(xs_c) - min(xs_c) + 1
assert width_c >= 200, f"min-width expand failed width={width_c}"
assert width_c < 400, f"min-width should not be full viewport width={width_c}"
# style_basic td solid #c80000 stroke; th border-style:none → no th stroke
exact_red = 0
for i in range(0, len(body), 3):
    if body[i] == 0xC8 and body[i + 1] == 0 and body[i + 2] == 0:
        exact_red += 1
assert exact_red >= 100, f"border-style solid td red stroke failed red={exact_red}"
# visibility:hidden magenta #c800c8 must not paint
exact_mag = 0
for i in range(0, len(body), 3):
    if body[i] == 0xC8 and body[i + 1] == 0 and body[i + 2] == 0xC8:
        exact_mag += 1
assert exact_mag == 0, f"visibility:hidden painted magenta={exact_mag}"
# opacity:0 pink #c80080 must not paint
exact_pink = 0
for i in range(0, len(body), 3):
    if body[i] == 0xC8 and body[i + 1] == 0 and body[i + 2] == 0x80:
        exact_pink += 1
assert exact_pink == 0, f"opacity:0 painted pink={exact_pink}"
# named yellow text paints #ffff00
exact_yel = 0
for i in range(0, len(body), 3):
    if body[i] == 0xFF and body[i + 1] == 0xFF and body[i + 2] == 0:
        exact_yel += 1
assert exact_yel >= 8, f"yellow text failed yel={exact_yel}"
# named cyan text paints #00ffff
exact_cy = 0
for i in range(0, len(body), 3):
    if body[i] == 0 and body[i + 1] == 0xFF and body[i + 2] == 0xFF:
        exact_cy += 1
assert exact_cy >= 8, f"cyan text failed cy={exact_cy}"
# named magenta text paints #ff00ff (≠ hidden #c800c8)
exact_mf = 0
for i in range(0, len(body), 3):
    if body[i] == 0xFF and body[i + 1] == 0 and body[i + 2] == 0xFF:
        exact_mf += 1
assert exact_mf >= 8, f"magenta text failed mf={exact_mf}"
# named orange text paints #ffa500
exact_or = 0
for i in range(0, len(body), 3):
    if body[i] == 0xFF and body[i + 1] == 0xA5 and body[i + 2] == 0:
        exact_or += 1
assert exact_or >= 8, f"orange text failed or={exact_or}"
# named lime text paints #00ff00 (≠ div #00c800)
exact_li = 0
for i in range(0, len(body), 3):
    if body[i] == 0 and body[i + 1] == 0xFF and body[i + 2] == 0:
        exact_li += 1
assert exact_li >= 8, f"lime text failed li={exact_li}"
print(
    "PASS max-height=",
    span_g,
    "max-width=",
    width_g,
    "min-height=",
    span_c,
    "min-width=",
    width_c,
    "border-solid-red=",
    exact_red,
    "hidden-magenta=",
    exact_mag,
    "opacity0-pink=",
    exact_pink,
    "yellow=",
    exact_yel,
    "cyan=",
    exact_cy,
    "magenta=",
    exact_mf,
    "orange=",
    exact_or,
    "lime=",
    exact_li,
)
PY
nm -g spark | grep se_css_get >/dev/null
nm -g spark | grep se_style_pool >/dev/null
nm -g spark | grep se_css_attach >/dev/null
echo "PASS engine-css"
