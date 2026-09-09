#!/usr/bin/env bash
# Decompile / dump a .sparkbc via real bc_dump (readable inspect).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "$HERE/../runtime/python/sparklang" ]] \
  || [[ -d "$HERE/../python/sparklang" ]]; then
  ROOT="$(cd "$HERE/.." && pwd)"
elif [[ -d "$HERE/../../runtime/python/sparklang" ]] \
  || [[ -d "$HERE/../../python/sparklang" ]]; then
  ROOT="$(cd "$HERE/../.." && pwd)"
else
  ROOT="$(cd "$HERE/../.." && pwd)"
fi
BC="${1:?usage: spark-helper-decompile <file.sparkbc> [out.txt]}"
OUT="${2:-}"
export PYTHONPATH="${ROOT}/tools:${ROOT}/python:${ROOT}/runtime/python:${PYTHONPATH:-}"
if [[ -n "$OUT" ]]; then
  python3 - <<PY
from pathlib import Path
import sys
sys.path.insert(0, "${ROOT}/tools")
from spark_bc_gui import core
text = core.decompile_sparkbc("$BC", root=Path("${ROOT}"))
Path("$OUT").write_text(text, encoding="utf-8")
print("wrote $OUT")
PY
else
  python3 - <<PY
from pathlib import Path
import sys
sys.path.insert(0, "${ROOT}/tools")
from spark_bc_gui import core
print(core.decompile_sparkbc("$BC", root=Path("${ROOT}")))
PY
fi
