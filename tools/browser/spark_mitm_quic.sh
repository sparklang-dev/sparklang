#!/usr/bin/env bash
# Spark companion: fork target for `mitm quic smoke` (asm).
# Invokes spark-browser aioquic MITM forge — Python is the helper
# only; language SoT remains .spark + asm/browser_ops.s.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
if [[ -d "$HERE/../spark-browser" ]]; then
  SPARK_ROOT="$HERE"
elif [[ -d "$HERE/../../spark-browser" ]]; then
  SPARK_ROOT="$(cd "$HERE/../.." && pwd)"
else
  echo "error: cannot find spark-browser next to spark/" >&2
  exit 1
fi
BROWSER="$(cd "$SPARK_ROOT/../spark-browser" && pwd)"
PY="$BROWSER/.venv/bin/python"
if [[ ! -x "$PY" ]]; then
  PY=python3
fi
export PYTHONPATH="$BROWSER${PYTHONPATH:+:$PYTHONPATH}"
exec "$PY" -m spark_browser.mitm.quic.smoke "$@"
