#!/usr/bin/env bash
# Spark companion: `mitm quic divert enable|disable|status`.
# Calls spark-browser/scripts/quic-udp-divert.sh ONLY for mutate when
# SPARK_QUIC_DIVERT=1 (then passes --apply). Dry-run / missing env →
# plan only (no host firewall change).
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
SCRIPT="$BROWSER/scripts/quic-udp-divert.sh"
if [[ ! -x "$SCRIPT" ]]; then
  chmod +x "$SCRIPT" 2>/dev/null || true
fi
if [[ ! -f "$SCRIPT" ]]; then
  echo "error: missing $SCRIPT" >&2
  exit 1
fi

cmd="${1:-status}"
shift || true
case "$cmd" in
  --enable|enable) cmd=enable ;;
  --disable|disable) cmd=disable ;;
  --status|status) cmd=status ;;
  --remove|remove) exec "$SCRIPT" --remove "$@" ;;
  *)
    echo "usage: spark-mitm-quic-divert enable|disable|status|remove" >&2
    exit 2
    ;;
esac

if [[ "$cmd" == "status" ]]; then
  exec "$SCRIPT" status "$@"
fi

# Mutate only when owner gate env is set.
if [[ "${SPARK_QUIC_DIVERT:-0}" == "1" ]]; then
  exec "$SCRIPT" "$cmd" --apply "$@"
fi
exec "$SCRIPT" "$cmd" "$@"
