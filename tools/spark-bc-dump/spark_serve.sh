#!/usr/bin/env bash
# spark-serve companion — tiny CPU forward via dump.py --serve.
# Not a production LLM. Never uses the voice GPU.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE"
if [[ ! -d "$ROOT/python/sparklang" ]]; then
  ROOT="$(cd "$HERE/../.." && pwd)"
fi
if [[ ! -d "$ROOT/python/sparklang" ]]; then
  echo "spark-serve: cannot find python/sparklang" >&2
  exit 1
fi
if [[ $# -lt 2 ]]; then
  echo "usage: spark-serve <file.sparkbc> <serve-dir> [extra dump.py args]" >&2
  exit 2
fi
SPARKBC="$1"
DEST="$2"
shift 2
export PYTHONPATH="${ROOT}/python${PYTHONPATH:+:$PYTHONPATH}"
exec python3 "${ROOT}/tools/spark-bc-dump/dump.py" \
  "$SPARKBC" --serve "$DEST" "$@"
