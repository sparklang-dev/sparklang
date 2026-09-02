#!/usr/bin/env bash
# btr → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/btr.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/btr.o" "$FIX"
"$ASM" --format=bin -o "$OUT/btr.bin" "$FIX"

python3 - "$OUT/btr.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rsi,43
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC6, 0x2B, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# mov rcx,0
assert b[7:14] == bytes([
    0x48, 0xC7, 0xC1, 0x00, 0x00, 0x00, 0x00,
]), b[7:14].hex()
# btr rsi,rcx — GAS: btr %rcx,%rsi → 48 0f b3 ce
assert b[14:18] == bytes([0x48, 0x0F, 0xB3, 0xCE]), b[14:18].hex()
print("btr bin OK", len(b), "bytes")
PY

objdump -d "$OUT/btr.o" | grep -q btr

ld -o "$OUT/btr" "$OUT/btr.o"
set +e
"$OUT/btr"
st=$?
set -e
test "$st" -eq 42

echo "test_btr OK (btr + exit 42)"
