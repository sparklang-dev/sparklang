#!/usr/bin/env bash
# Launch SparkLang SPARK_BC graphical compile / decompile.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# Repo: tools/spark-bc-gui/launch.sh → ROOT=../..
# Pack: bin/spark-bc-gui → ROOT=..
if [[ -d "$HERE/../python/sparklang" ]]; then
  ROOT="$(cd "$HERE/.." && pwd)"
  GUI_DIR="$HERE"
elif [[ -d "$HERE/../runtime/python/sparklang" ]]; then
  ROOT="$(cd "$HERE/.." && pwd)"
  GUI_DIR="$ROOT/gui/spark-bc-gui"
elif [[ -d "$HERE/../../python/sparklang" ]]; then
  ROOT="$(cd "$HERE/../.." && pwd)"
  GUI_DIR="$HERE"
else
  ROOT="$(cd "$HERE/../.." && pwd)"
  GUI_DIR="$HERE"
fi

export PYTHONPATH="${ROOT}/tools:${ROOT}/python:${ROOT}/runtime/python:${GUI_DIR}/..:${PYTHONPATH:-}"
cd "$ROOT"

if [[ -x "$ROOT/spark-bootstrap" ]]; then
  :
elif [[ -x "$ROOT/bin/spark-bootstrap" ]]; then
  :
else
  echo "spark-bc-gui: building spark-bootstrap…" >&2
  make -C "$ROOT" spark-bootstrap
fi

exec python3 -m spark_bc_gui "$@"
