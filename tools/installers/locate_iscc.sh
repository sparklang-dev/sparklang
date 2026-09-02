#!/usr/bin/env bash
# Locate ISCC (native or Wine) for Inno Setup builds on Linux.
set -euo pipefail

if command -v iscc >/dev/null 2>&1; then
  echo "iscc"
  exit 0
fi

INNO_DIRS=(
  "$HOME/.local/share/inno-setup-wine/drive_c/InnoSetup6"
  "$HOME/.wine/drive_c/inno-setup-6"
  "$HOME/.wine/drive_c/Program Files (x86)/Inno Setup 6"
  "$HOME/.wine/drive_c/Program Files/Inno Setup 6"
  "/opt/inno-setup"
  "$HOME/.local/share/inno-setup-6"
)

for dir in "${INNO_DIRS[@]}"; do
  if [[ -f "$dir/ISCC.exe" ]]; then
    prefix="$(cd "$(dirname "$dir")/.." && pwd)"
    printf 'env WINEPREFIX=%q xvfb-run -a wine %q\n' "$prefix" "$dir/ISCC.exe"
    exit 0
  fi
done

exit 1
