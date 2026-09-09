#!/usr/bin/env bash
# spark-model-lab companion (installed to repo root as ./spark-model-lab).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE"
if [[ ! -d "$ROOT/python/sparklang" ]]; then
  ROOT="$(cd "$HERE/../.." && pwd)"
fi
if [[ ! -d "$ROOT/python/sparklang" ]]; then
  echo "spark-model-lab: cannot find python/sparklang" >&2
  exit 1
fi
export PYTHONPATH="${ROOT}/python${PYTHONPATH:+:$PYTHONPATH}"
exec python3 "${ROOT}/tools/spark-model-lab/cli.py" "$@"
