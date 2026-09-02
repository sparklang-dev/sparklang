#!/usr/bin/env bash
# .byte + lea reg, label + movzx byte [reg+disp]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/byte_lea.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/byte_lea.o" "$FIX"
ld -o "$OUT/byte_lea" "$OUT/byte_lea.o"
set +e
"$OUT/byte_lea"
st=$?
set -e
test "$st" -eq 7
echo "test_byte_lea OK (exit 7)"
