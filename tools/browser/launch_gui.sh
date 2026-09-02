#!/usr/bin/env bash
# Temporary Qt host shim for Spark `browser gui` (asm fork/exec).
# SoT = .spark + asm/browser_ops.s — this helper is not the product.
# MITM forge is Spark-owned (`mitm enable` → spark-mitm-h2); UI attaches.
# Default: QUIC ON. Optional --disable-quic for TCP h2/h1-only MITM.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PRODUCT="${SPARK_BROWSER_ROOT:-}"
if [[ -z "$PRODUCT" || ! -d "$PRODUCT/spark_browser" ]]; then
  PRODUCT="$(cd "$ROOT/../spark-browser" && pwd)"
fi
URL="https://example.com/"
INSECURE=0
ENABLE_QUIC=1
OWN_MITM=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      URL="$2"
      shift 2
      ;;
    --insecure|--ignore-certificate-errors)
      INSECURE=1
      shift
      ;;
    --enable-quic)
      ENABLE_QUIC=1
      shift
      ;;
    --disable-quic)
      ENABLE_QUIC=0
      shift
      ;;
    --own-mitm)
      OWN_MITM=1
      shift
      ;;
    *)
      shift
      ;;
  esac
done
export PYTHONPATH="${PRODUCT}${PYTHONPATH:+:$PYTHONPATH}"
FLAGS="${QTWEBENGINE_CHROMIUM_FLAGS:-}"
if [[ "$ENABLE_QUIC" -eq 0 && "$FLAGS" != *"--disable-quic"* ]]; then
  FLAGS="${FLAGS:+$FLAGS }--disable-quic"
fi
if [[ "$INSECURE" -eq 1 && "$FLAGS" != *"--ignore-certificate-errors"* ]]; then
  FLAGS="${FLAGS:+$FLAGS }--ignore-certificate-errors"
fi
export QTWEBENGINE_CHROMIUM_FLAGS="$FLAGS"
cd "$PRODUCT"
args=(run --url "$URL")
if [[ "$INSECURE" -eq 1 ]]; then
  args+=(--ignore-certificate-errors)
fi
if [[ "$ENABLE_QUIC" -eq 0 ]]; then
  args+=(--disable-quic)
else
  args+=(--enable-quic)
fi
if [[ "$OWN_MITM" -eq 1 ]]; then
  args+=(--own-mitm)
fi
exec python3 -m spark_browser "${args[@]}"
