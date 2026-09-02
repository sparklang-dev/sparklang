#!/usr/bin/env bash
# Build macOS .pkg per CPU arch (flat xar on Linux, pkgbuild on Darwin).
set -euo pipefail

INSTALLERS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$INSTALLERS/common.sh"

VERSION="${1:?usage: build_macos_pkg.sh VERSION STAGE_DIR OUT_DIR [ARCH]}"
STAGE_DIR="${2:?}"
OUT_DIR="${3:?}"
ARCH="${4:-arm64}"

ARCH="$(normalize_arch "$ARCH")"
PKG_NAME="spark-runtime-macos-${ARCH}-${VERSION}.pkg"
WORK="$STAGE_DIR/macos-pkg-${ARCH}"
PAYLOAD="$WORK/payload/usr/local/spark"
SCRIPTS="$WORK/scripts"
RESOURCES="$WORK/resources"

rm -rf "$WORK"
mkdir -p "$PAYLOAD" "$SCRIPTS" "$RESOURCES/en.lproj" "$OUT_DIR"

cp "$INSTALLERS/assets/welcome.html" "$RESOURCES/en.lproj/welcome.html"
cp "$INSTALLERS/assets/conclusion.html" "$RESOURCES/en.lproj/conclusion.html"

stage_portable_kit macos "$PAYLOAD" "$ARCH"

cat >"$PAYLOAD/README.txt" <<EOF
Spark AI runtime — macOS ${ARCH} (${VERSION})
==============================================

Portable bootstrap + sparkasm source kit with AI examples.
The installer places files in /usr/local/spark and runs build.sh once
to compile for ${ARCH} on this Mac.

After install:
  /usr/local/spark/bin/spark-bootstrap --dry-run /usr/local/spark/examples/hello.spark

For the full Linux x86_64 prebuilt stack (spark-ask-http, speech, gateway),
use the Linux x86_64 package or build from source on Linux.
Docs: https://sparklang.dev/docs/programming-guide.html
EOF

cat >"$SCRIPTS/postinstall" <<'POST'
#!/bin/sh
set -e
PREFIX="/usr/local/spark"
cd "$PREFIX"
if [ -x ./build.sh ]; then
  echo "Building spark-bootstrap and sparkasm (first run)..."
  ./build.sh
fi
echo "Spark runtime ready under $PREFIX"
echo "Try: $PREFIX/bin/spark-bootstrap --dry-run $PREFIX/examples/hello.spark"
POST
chmod 755 "$SCRIPTS/postinstall"

if command -v pkgbuild >/dev/null 2>&1 && command -v productbuild >/dev/null 2>&1; then
  PKGROOT="$WORK/pkgroot"
  rm -rf "$PKGROOT"
  mkdir -p "$PKGROOT/usr/local"
  cp -a "$PAYLOAD" "$PKGROOT/usr/local/spark"
  pkgbuild --root "$PKGROOT" \
    --identifier "dev.sparklang.runtime.${ARCH}" \
    --version "$VERSION" \
    --scripts "$SCRIPTS" \
    --resources "$RESOURCES" \
    "$OUT_DIR/$PKG_NAME"
  echo "Built (native pkgbuild) $OUT_DIR/$PKG_NAME"
else
  PAYLOAD_ONLY="$WORK/payload-only"
  rm -rf "$PAYLOAD_ONLY"
  mkdir -p "$PAYLOAD_ONLY/usr/local"
  cp -a "$PAYLOAD" "$PAYLOAD_ONLY/usr/local/spark"
  python3 "$INSTALLERS/make_flat_pkg.py" \
    "$PAYLOAD_ONLY" \
    "$OUT_DIR/$PKG_NAME" \
    "dev.sparklang.runtime.${ARCH}" \
    "$VERSION" \
    "$SCRIPTS/postinstall" \
    "$RESOURCES"
  echo "Built (flat xar) $OUT_DIR/$PKG_NAME"
fi
