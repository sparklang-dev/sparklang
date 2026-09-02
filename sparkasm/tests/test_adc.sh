#!/usr/bin/env bash
# adc reg,reg → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/adc.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/adc.o" "$FIX"
"$ASM" --format=bin -o "$OUT/adc.bin" "$FIX"

python3 - "$OUT/adc.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,41
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC7, 0x29, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# mov rsi,1
assert b[7:14] == bytes([
    0x48, 0xC7, 0xC6, 0x01, 0x00, 0x00, 0x00,
]), b[7:14].hex()
# adc rdi,rsi — GAS: adc %rsi,%rdi → 48 11 f7
assert b[14:17] == bytes([0x48, 0x11, 0xF7]), b[14:17].hex()
print("adc bin OK", len(b), "bytes")
PY

objdump -d "$OUT/adc.o" | grep -q adc

ld -o "$OUT/adc" "$OUT/adc.o"
set +e
"$OUT/adc"
st=$?
set -e
test "$st" -eq 42

echo "test_adc OK (adc reg,reg + exit 42)"
