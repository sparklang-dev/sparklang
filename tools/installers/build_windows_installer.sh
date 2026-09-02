#!/usr/bin/env bash
# Build Windows installer zip per CPU arch (.exe via Inno when iscc present).
set -euo pipefail

INSTALLERS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$INSTALLERS/common.sh"

VERSION="${1:?usage: build_windows_installer.sh VERSION STAGE_DIR OUT_DIR [ARCH]}"
STAGE_DIR="${2:?}"
OUT_DIR="${3:?}"
ARCH="${4:-x86_64}"

ARCH="$(normalize_arch "$ARCH")"
KIT_NAME="spark-runtime-windows-${ARCH}-${VERSION}"
STAGE_KIT="$STAGE_DIR/$KIT_NAME"
EXE_NAME="spark-runtime-windows-${ARCH}-${VERSION}-setup.exe"
ZIP_NAME="spark-runtime-windows-${ARCH}-${VERSION}-setup.zip"

rm -rf "$STAGE_KIT"
mkdir -p "$STAGE_KIT" "$OUT_DIR"

stage_portable_kit windows "$STAGE_KIT" "$ARCH"

cat >"$STAGE_KIT/README.txt" <<EOF
Spark AI runtime — Windows ${ARCH} (${VERSION})
===============================================

Portable bootstrap + sparkasm source kit with AI examples.
Run Setup.bat (or build.bat) once to compile on this machine (${ARCH}).

After build:
  bin\\spark-bootstrap --dry-run examples\\hello.spark

For the full Linux x86_64 prebuilt stack (spark-ask-http, speech, gateway),
use WSL + the Linux x86_64 package or build from source.
Docs: https://sparklang.dev/docs/programming-guide.html
EOF

cat >"$STAGE_KIT/Setup.bat" <<'SETUP'
@echo off
setlocal
cd /d "%~dp0"
echo Spark AI runtime — first-run build
echo ==================================
where bash >nul 2>&1
if errorlevel 1 (
  echo Git Bash or WSL is required to compile Spark on Windows.
  echo Install Git for Windows, then re-run Setup.bat
  pause
  exit /b 1
)
call build.bat
if errorlevel 1 (
  echo Build failed.
  pause
  exit /b 1
)
echo.
echo Ready. Dry-run offline:
echo   bin\spark-bootstrap --dry-run examples\hello.spark
echo.
pause
SETUP

if ISCC_CMD="$(bash "$INSTALLERS/locate_iscc.sh" 2>/dev/null)"; then
  WIN_STAGE="$INSTALLERS/.win-stage"
  WIN_OUT="$INSTALLERS/.win-out"
  rm -rf "$WIN_STAGE" "$WIN_OUT"
  mkdir -p "$WIN_STAGE" "$WIN_OUT"
  cp -a "$STAGE_KIT" "$WIN_STAGE/"
  REL_ISS="tools/installers/build_windows_inno.iss"
  (
    cd "$ROOT"
    # shellcheck disable=SC2086
    eval "$ISCC_CMD" "/DVERSION=${VERSION}" "/DSTAGE=.win-stage" \
      "/DOUT=.win-out" "/DARCH=${ARCH}" "$REL_ISS"
  )
  built="$WIN_OUT/$EXE_NAME"
  if [[ -f "$built" ]]; then
    mv "$built" "$OUT_DIR/$EXE_NAME"
    echo "Built graphical installer $OUT_DIR/$EXE_NAME"
    rm -rf "$WIN_STAGE" "$WIN_OUT"
    exit 0
  fi
  rm -rf "$WIN_STAGE" "$WIN_OUT"
fi

echo "==> Inno Setup (iscc/wine) unavailable — zip + Setup.bat fallback for windows-${ARCH}"
(
  cd "$STAGE_DIR"
  zip -rq "$OUT_DIR/$ZIP_NAME" "$KIT_NAME"
)
echo "Built $OUT_DIR/$ZIP_NAME (extract and run Setup.bat — compiles on first run)"
