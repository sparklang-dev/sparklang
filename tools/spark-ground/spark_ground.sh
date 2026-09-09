#!/usr/bin/env bash
# spark-ground companion (installed to repo root as ./spark-ground).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE"
if [[ ! -d "$ROOT/python/sparklang" ]]; then
  ROOT="$(cd "$HERE/../.." && pwd)"
fi
if [[ ! -d "$ROOT/python/sparklang" ]]; then
  echo "spark-ground: cannot find python/sparklang" >&2
  exit 1
fi
export PYTHONPATH="${ROOT}/python${PYTHONPATH:+:$PYTHONPATH}"
exec python3 "${ROOT}/tools/spark-ground/cli.py" "$@"
