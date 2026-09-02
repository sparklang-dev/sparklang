#!/usr/bin/env bash
# Spark companion: fork target for `mitm ca-init|enable|smoke|…`.
# Protocol forge lives under spark-browser; language SoT is .spark + asm.
# Python here is NOT the product — Spark owns the ops via fork_exec_wait.
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
export SPARK_MITM_CA_DIR="${SPARK_MITM_CA_DIR:-$BROWSER/data/ca}"
export SPARK_MITM_SESSION_DIR="${SPARK_MITM_SESSION_DIR:-$BROWSER/sessions/latest}"
exec "$PY" -m spark_browser.mitm.spark_owned "$@"
