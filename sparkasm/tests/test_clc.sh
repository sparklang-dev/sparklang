#!/usr/bin/env bash
# stc/clc + adc → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/clc.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/clc.o" "$FIX"
"$ASM" --format=bin -o "$OUT/clc.bin" "$FIX"

python3 - "$OUT/clc.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,42
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC7, 0x2A, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# mov rsi,0
assert b[7:14] == bytes([
    0x48, 0xC7, 0xC6, 0x00, 0x00, 0x00, 0x00,
]), b[7:14].hex()
# stc — GAS: f9
assert b[14] == 0xF9, hex(b[14])
# clc — GAS: f8
assert b[15] == 0xF8, hex(b[15])
# adc rdi,rsi — GAS: 48 11 f7
assert b[16:19] == bytes([0x48, 0x11, 0xF7]), b[16:19].hex()
print("clc bin OK", len(b), "bytes")
PY

objdump -d "$OUT/clc.o" | grep -q clc

ld -o "$OUT/clc" "$OUT/clc.o"
set +e
"$OUT/clc"
st=$?
set -e
test "$st" -eq 42

echo "test_clc OK (stc/clc + adc + exit 42)"
