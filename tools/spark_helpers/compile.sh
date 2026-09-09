#!/usr/bin/env bash
# Compile a .spark file to .sparkbc via real spark-bootstrap --compile.
set -euo pipefail
# Resolve pack/repo root whether invoked from helpers/ or tools/spark_helpers/
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -x "$HERE/../bin/spark-bootstrap" ]] \
  || [[ -x "$HERE/../spark-bootstrap" ]]; then
  ROOT="$(cd "$HERE/.." && pwd)"
elif [[ -x "$HERE/../../bin/spark-bootstrap" ]]; then
  ROOT="$(cd "$HERE/../.." && pwd)"
else
  ROOT="$(cd "$HERE/../.." && pwd)"
fi
if [[ -x "$ROOT/bin/spark-bootstrap" ]]; then
  BOOT="$ROOT/bin/spark-bootstrap"
elif [[ -x "$ROOT/spark-bootstrap" ]]; then
  BOOT="$ROOT/spark-bootstrap"
else
  echo "spark-helper-compile: build spark-bootstrap first" >&2
  exit 1
fi
SRC="${1:?usage: spark-helper-compile <file.spark> [out.sparkbc]}"
OUT="${2:-${SRC%.spark}.sparkbc}"
exec "$BOOT" --compile "$SRC" -o "$OUT"
