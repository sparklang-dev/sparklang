#!/usr/bin/env bash
# Shadow-verify: compare shadow-built .sparkbc to a golden / published file.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NAME="${1:-default}"
DEST="${SPARK_SHADOW_ROOT:-$ROOT/out/shadow}/$NAME"
GOT="$DEST/out/shadow-build/sample.sparkbc"
GOLDEN="${2:-$ROOT/docs/examples/spark-self.sparkbc}"
if [[ ! -f "$GOT" ]]; then
  echo "shadow-verify: missing $GOT — run shadow-build first" >&2
  exit 1
fi
if [[ ! -f "$GOLDEN" ]]; then
  echo "shadow-verify: missing golden $GOLDEN" >&2
  exit 1
fi
GOT_SHA="$(sha256sum "$GOT" | awk '{print $1}')"
GOLD_SHA="$(sha256sum "$GOLDEN" | awk '{print $1}')"
echo "got     $GOT_SHA  $GOT"
echo "golden  $GOLD_SHA  $GOLDEN"
if [[ "$GOT_SHA" == "$GOLD_SHA" ]]; then
  echo "shadow-verify PASS (sha256 match)"
  exit 0
fi
# Honest miss is OK for samples that differ from golden — still useful
# as a byte-presence check. Exit 2 = mismatch (not crash).
echo "shadow-verify MISMATCH (bytes differ — inspect dumps)" >&2
# Still prove both decode as SPARK_BC
export PYTHONPATH="${ROOT}/tools:${ROOT}/python:${DEST}/python:${PYTHONPATH:-}"
python3 - <<PY
from pathlib import Path
import sys
sys.path.insert(0, "${ROOT}/tools")
from spark_bc_gui import core
for p in ("$GOT", "$GOLDEN"):
    t = core.decompile_sparkbc(p, root=Path("${ROOT}"))
    assert "magic: SPBC" in t, p
print("both files decode as SPARK_BC")
PY
exit 2
