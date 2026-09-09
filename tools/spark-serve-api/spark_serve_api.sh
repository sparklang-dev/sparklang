#!/usr/bin/env bash
# spark-serve-api — tiny CPU HTTP/stdio predict + embeddings.
# Wraps model_lab.serve_api. Not production. Never the voice GPU.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE"
if [[ ! -d "$ROOT/python/sparklang" ]]; then
  ROOT="$(cd "$HERE/../.." && pwd)"
fi
if [[ ! -d "$ROOT/python/sparklang" ]]; then
  echo "spark-serve-api: cannot find python/sparklang" >&2
  exit 1
fi
export PYTHONPATH="${ROOT}/python${PYTHONPATH:+:$PYTHONPATH}"
exec python3 -m sparklang.model_lab.serve_api "$@"
