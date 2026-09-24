#!/usr/bin/env bash
# spark-serve-ref companion (installed as ./spark-serve-ref).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE"
if [[ ! -d "$ROOT/tools/spark-serve-ref" ]]; then
  ROOT="$(cd "$HERE/../.." && pwd)"
fi
if [[ ! -f "$ROOT/tools/spark-serve-ref/server.py" ]]; then
  echo "spark-serve-ref: cannot find tools/spark-serve-ref/server.py" >&2
  exit 1
fi
exec python3 "$ROOT/tools/spark-serve-ref/server.py" "$@"
