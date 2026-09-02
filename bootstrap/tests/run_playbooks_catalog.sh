#!/usr/bin/env bash
# Gate: playbooks-catalog.json matches lib/playbooks.spark + fixtures.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
python3 tools/gen_playbooks_catalog.py >/dev/null
JSON=website/data/playbooks-catalog.json
SNIP=tools/spark-ide-extension/snippets/playbooks.json
[[ -f "$JSON" ]] || { echo "FAIL missing $JSON"; exit 1; }
[[ -f "$SNIP" ]] || { echo "FAIL missing $SNIP"; exit 1; }
python3 - <<'PY'
import json
import re
from pathlib import Path

root = Path(".")
lib = (root / "lib" / "playbooks.spark").read_text(encoding="utf-8")
names = re.findall(r"^#\s*@playbook\s+(\w+)\s*$", lib, re.M)
data = json.loads((root / "website/data/playbooks-catalog.json").read_text())
entries = {e["id"]: e for e in data["entries"]}
fail = 0
for name in names:
    e = entries.get(name)
    if not e:
        print(f"FAIL catalog missing playbook {name}")
        fail = 1
        continue
    fx = root / "bootstrap/fixtures/playbooks" / f"{name}.spark"
    if not fx.is_file():
        print(f"FAIL missing fixture {fx}")
        fail = 1
        continue
    want = fx.read_text(encoding="utf-8").rstrip() + "\n"
    if e.get("source") != want:
        print(f"FAIL source drift for {name}")
        fail = 1
        continue
    if e.get("siteRun") != "download-required":
        print(f"FAIL siteRun not download-required for {name}")
        fail = 1
        continue
    print(f"PASS {name}")
if data.get("playbookCount") != len(names):
    print(
        f"FAIL playbookCount {data.get('playbookCount')} != {len(names)}"
    )
    fail = 1
snip = json.loads(
    (root / "tools/spark-ide-extension/snippets/playbooks.json").read_text()
)
for name in names:
    key = f"Spark playbook: {name}"
    if key not in snip:
        print(f"FAIL snippet missing {key}")
        fail = 1
    else:
        print(f"PASS snip {name}")
for eid in entries:
    fx = root / "bootstrap/fixtures/playbooks" / f"{eid}.spark"
    if not fx.is_file():
        print(f"FAIL invented entry without fixture: {eid}")
        fail = 1
raise SystemExit(fail)
PY
echo "playbooks-catalog gate OK"
