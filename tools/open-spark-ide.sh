#!/usr/bin/env bash
# Open Spark IDE (Cursor + Bifrost AI coding) for the Spark language.
set -euo pipefail

SPARK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WS="${SPARK_ROOT}/spark.code-workspace"
EXT="${SPARK_ROOT}/tools/spark-ide-extension"
CURSOR_BIN="${CURSOR_BIN:-/usr/share/cursor/cursor}"

if [[ ! -f "$WS" ]]; then
  echo "missing workspace: $WS" >&2
  exit 1
fi

# Best-effort local language extension (syntax for .spark). Non-fatal.
if [[ -d "$EXT" ]] && command -v cursor >/dev/null 2>&1; then
  cursor --install-extension "$EXT" >/dev/null 2>&1 || true
fi

export AI_GATEWAY_URL="${AI_GATEWAY_URL:-http://127.0.0.1:4000}"
export SPARK_IDE=1

exec env XCURSOR_SIZE="${XCURSOR_SIZE:-24}" \
  "$CURSOR_BIN" --new-window "$WS"
