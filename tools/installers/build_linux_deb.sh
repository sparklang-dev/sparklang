#!/usr/bin/env bash
# Build unsigned .deb for Spark AI runtime (Linux per CPU arch).
set -euo pipefail

INSTALLERS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$INSTALLERS/common.sh"

VERSION="${1:?usage: build_linux_deb.sh VERSION STAGE_DIR OUT_DIR [ARCH] [KIND]}"
STAGE_DIR="${2:?}"
OUT_DIR="${3:?}"
ARCH="${4:-x86_64}"
KIND="${5:-prebuilt}"

ARCH="$(normalize_arch "$ARCH")"
DEB_ARCH="$(deb_arch_for "$ARCH")"
DEB_NAME="spark-runtime-linux-${ARCH}-${VERSION}.deb"
PREFIX="/opt/spark"

rm -rf "$STAGE_DIR/deb-root-${ARCH}"
PKGROOT="$STAGE_DIR/deb-root-${ARCH}"
mkdir -p "$PKGROOT/DEBIAN" "$PKGROOT$PREFIX/bin" "$PKGROOT$PREFIX/examples"
mkdir -p "$PKGROOT$PREFIX/share/doc/spark-runtime"

if [[ "$KIND" == "prebuilt" ]]; then
  stage_linux_full "$PKGROOT$PREFIX"
  DESCRIPTION="Spark AI-first language runtime (prebuilt ${ARCH})"
  POST_BUILD=""
elif [[ "$KIND" == "hybrid" ]]; then
  stage_linux_arm64_hybrid "$PKGROOT$PREFIX"
  DESCRIPTION="Spark AI runtime hybrid (${ARCH}) — bootstrap VM + C companions"
  POST_BUILD=""
else
  stage_portable_kit linux "$PKGROOT$PREFIX" "$ARCH"
  DESCRIPTION="Spark AI runtime bootstrap kit (${ARCH}) — builds on first install"
  POST_BUILD=1
fi

cp "$PKGROOT$PREFIX/runtime-ai-guide.txt" "$PKGROOT$PREFIX/share/doc/spark-runtime/"

# Graphical installer (zenity/yad wizard + Applications menu entry)
GUI_SRC="$INSTALLERS/spark-install-gui.sh"
DESKTOP_SRC="$INSTALLERS/spark-installer.desktop"
ICON_SRC="$ROOT/website/favicon.svg"
mkdir -p "$PKGROOT$PREFIX/bin" \
  "$PKGROOT/usr/share/applications" \
  "$PKGROOT/usr/share/icons/hicolor/scalable/apps"
sed "s/^VERSION=.*/VERSION=\"${VERSION}\"/" "$GUI_SRC" \
  >"$PKGROOT$PREFIX/bin/spark-install-gui"
chmod 755 "$PKGROOT$PREFIX/bin/spark-install-gui"
install -m 644 "$DESKTOP_SRC" "$PKGROOT/usr/share/applications/spark-installer.desktop"
if [[ -f "$ICON_SRC" ]]; then
  install -m 644 "$ICON_SRC" \
    "$PKGROOT/usr/share/icons/hicolor/scalable/apps/spark-installer.svg"
fi

cat >"$PKGROOT/DEBIAN/control" <<EOF
Package: spark-runtime
Version: ${VERSION}
Section: devel
Priority: optional
Architecture: ${DEB_ARCH}
Maintainer: Spark Language <https://sparklang.dev>
Description: ${DESCRIPTION}
 Bootstrap VM, sparkasm, and AI example programs. Dry-run offline;
 live ask via OpenAI-compatible APIs on prebuilt x86_64; other arches
 compile locally via build.sh on first install.
Homepage: https://sparklang.dev
EOF

if [[ -n "$POST_BUILD" ]]; then
  cat >"$PKGROOT/DEBIAN/postinst" <<'POST'
#!/bin/sh
set -e
PREFIX="/opt/spark"
cd "$PREFIX"
if [ -x ./build.sh ]; then
  echo "Building spark-bootstrap and sparkasm for this CPU (first install)..."
  ./build.sh
fi
echo "Spark runtime ready under $PREFIX"
echo "Try: $PREFIX/bin/spark-bootstrap --dry-run $PREFIX/examples/hello.spark"
POST
else
  cat >"$PKGROOT/DEBIAN/postinst" <<POST
#!/bin/sh
set -e
PREFIX="/opt/spark"
BINDIR="/usr/local/bin"
mkdir -p "\$BINDIR"
for b in spark spark-bc spark-bootstrap spark-ask-http spark-ask-probe spark-enc-gateway \\
  spark-stt-tts spark-review-url sparkasm spark-gas-legacy; do
  if [ -x "\$PREFIX/bin/\$b" ]; then
    ln -sf "\$PREFIX/bin/\$b" "\$BINDIR/\$b"
  fi
done
echo "Spark ${VERSION} installed to \$PREFIX (bin symlinks in \$BINDIR)"
if [ -x "\$PREFIX/bin/spark-bc" ]; then
  echo "Primary CLI: spark-bc (compile → bc_vm when supported)"
fi
if [ -x "\$PREFIX/bin/spark-gas-legacy" ]; then
  echo "Legacy GAS VM: spark-gas-legacy (x86_64 asm compare / --live)"
fi
echo "Graphical helper: /opt/spark/bin/spark-install-gui (also in Applications menu)"
echo "Try: spark-bc \$PREFIX/examples/hello.spark"
POST
fi
chmod 755 "$PKGROOT/DEBIAN/postinst"

mkdir -p "$OUT_DIR"
fakeroot dpkg-deb --build --root-owner-group "$PKGROOT" "$OUT_DIR/$DEB_NAME"
echo "Built $OUT_DIR/$DEB_NAME ($(du -h "$OUT_DIR/$DEB_NAME" | awk '{print $1}')) kind=${KIND}"
