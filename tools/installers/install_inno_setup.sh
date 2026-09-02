#!/usr/bin/env bash
# Install Inno Setup 6 under Wine for headless ISCC builds on Linux.
set -euo pipefail

INSTALLERS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=locate_iscc.sh
if bash "$INSTALLERS/locate_iscc.sh" >/dev/null 2>&1; then
  echo "Inno Setup already available: $(bash "$INSTALLERS/locate_iscc.sh")"
  exit 0
fi

INNO_URL="${INNO_SETUP_URL:-https://github.com/jrsoftware/issrc/releases/download/is-6_7_3/innosetup-6.7.3.exe}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Downloading Inno Setup from $INNO_URL"
curl -fsSL -o "$TMP/innosetup.exe" "$INNO_URL"

echo "==> Installing Inno Setup under Wine (dedicated WINEPREFIX)"
export WINEPREFIX="${INNO_WINEPREFIX:-$HOME/.local/share/inno-setup-wine}"
export WINEARCH=win64
wineboot --init 2>/dev/null || true
if command -v xvfb-run >/dev/null 2>&1; then
  timeout 180 xvfb-run -a wine "$TMP/innosetup.exe" \
    /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /NOICONS /DIR=C:\\InnoSetup6
else
  timeout 180 wine "$TMP/innosetup.exe" \
    /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /NOICONS /DIR=C:\\InnoSetup6
fi

if bash "$INSTALLERS/locate_iscc.sh"; then
  echo "Inno Setup installed."
else
  echo "Inno Setup install finished but ISCC.exe not found" >&2
  exit 1
fi
