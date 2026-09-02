#!/usr/bin/env bash
# Engine B HTML parse→DOM fixture test (asm only).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
make -s spark

rm -rf out/browser/engine
./spark --dry-run examples/engine_parse.spark >/tmp/spark-engine-parse.out

test -f out/browser/engine/dom.json
grep -q '"op":"engine.parse"' out/browser/engine/dom.json
grep -q '"ok":true' out/browser/engine/dom.json
grep -q '"engine":"spark-asm-html"' out/browser/engine/dom.json

python3 - <<'PY'
import json
from pathlib import Path

d = json.loads(Path("out/browser/engine/dom.json").read_text())
assert d["ok"] is True
assert d["nnodes"] >= 14, d["nnodes"]
assert d["nelements"] >= 12, d["nelements"]
assert d["ntexts"] >= 3, d["ntexts"]
assert d["root"] >= 0
tc = d["tag_counts"]
assert tc.get("html", 0) >= 1
assert tc.get("h1", 0) >= 1
assert tc.get("p", 0) >= 1
assert tc.get("div", 0) >= 1
assert tc.get("ul", 0) >= 1
assert tc.get("li", 0) >= 2
assert tc.get("img", 0) >= 1
assert tc.get("a", 0) >= 1
assert tc.get("table", 0) >= 1
assert tc.get("tr", 0) >= 1
assert tc.get("td", 0) >= 1
assert tc.get("th", 0) >= 1
tags = {n.get("tag") for n in d["nodes"] if n.get("k") == "e"}
assert "body" in tags and "h1" in tags
assert "table" in tags and "tr" in tags and "td" in tags and "th" in tags
assert "img" in tags
texts = [n.get("text", "") for n in d["nodes"] if n.get("k") == "t"]
blob = " ".join(texts)
assert "Hello Spark" in blob
assert "Parse to DOM" in blob
assert "cell" in blob
for n in d["nodes"]:
    assert "p" in n and "fc" in n and "ns" in n
by_id = {n["id"]: n for n in d["nodes"]}
assert by_id[4]["tag"] == "body" and by_id[4]["p"] == 0
assert by_id[1]["ns"] == 4
assert by_id[7]["tag"] == "p" and by_id[7]["p"] == 4
assert by_id[12]["tag"] == "a" and by_id[12]["p"] == 9
assert by_id[17]["tag"] == "li" and by_id[17]["p"] == 14
print(
    "PASS engine_html_parse",
    "nnodes=", d["nnodes"],
    "nelements=", d["nelements"],
    "ntexts=", d["ntexts"],
)
PY
