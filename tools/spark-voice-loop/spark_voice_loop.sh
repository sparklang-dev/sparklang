#!/usr/bin/env bash
# spark-voice-loop companion (installed as ./spark-voice-loop).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE"
if [[ ! -d "$ROOT/python/sparklang" ]]; then
  ROOT="$(cd "$HERE/../.." && pwd)"
fi
export PYTHONPATH="${ROOT}/python${PYTHONPATH:+:$PYTHONPATH}"
exec python3 "${ROOT}/python/sparklang/voice_loop/stmt.py" "$@"
