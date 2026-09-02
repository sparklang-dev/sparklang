#!/usr/bin/env bash
# Spark AI runtime installer — macOS (auto-detect arm64 vs x86_64)
set -euo pipefail
VERSION="0.6.0"
BASE="https://sparklang.dev/downloads"
case "$(uname -m)" in
  arm64|aarch64) ARCH=arm64 ;;
  x86_64) ARCH=x86_64 ;;
  *) echo "Unsupported Mac CPU: $(uname -m)" >&2; exit 1 ;;
esac
PKG="spark-runtime-macos-${ARCH}-${VERSION}.pkg"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
echo "==> Downloading ${PKG} for ${ARCH}"
curl -fsSL "${BASE}/${PKG}" -o "$tmpdir/${PKG}"
echo "==> Installing (may prompt for password)"
sudo installer -pkg "$tmpdir/${PKG}" -target /
echo "Done. Try: /usr/local/spark/bin/spark-bc /usr/local/spark/examples/hello.spark"
