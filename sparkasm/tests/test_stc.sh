#!/usr/bin/env bash
# stc + adc → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/stc.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/stc.o" "$FIX"
"$ASM" --format=bin -o "$OUT/stc.bin" "$FIX"

python3 - "$OUT/stc.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,41
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC7, 0x29, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# mov rsi,0
assert b[7:14] == bytes([
    0x48, 0xC7, 0xC6, 0x00, 0x00, 0x00, 0x00,
]), b[7:14].hex()
# stc — GAS: stc → f9
assert b[14] == 0xF9, hex(b[14])
# adc rdi,rsi — GAS: adc %rsi,%rdi → 48 11 f7
assert b[15:18] == bytes([0x48, 0x11, 0xF7]), b[15:18].hex()
print("stc bin OK", len(b), "bytes")
PY

objdump -d "$OUT/stc.o" | grep -q stc

ld -o "$OUT/stc" "$OUT/stc.o"
set +e
"$OUT/stc"
st=$?
set -e
test "$st" -eq 42

echo "test_stc OK (stc + adc + exit 42)"
