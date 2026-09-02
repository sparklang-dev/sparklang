#!/usr/bin/env bash
# shl reg,cl → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/shiftcl.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/shiftcl.o" "$FIX"
"$ASM" --format=bin -o "$OUT/shiftcl.bin" "$FIX"

python3 - "$OUT/shiftcl.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,21
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC7, 0x15, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# mov rcx,1
assert b[7:14] == bytes([
    0x48, 0xC7, 0xC1, 0x01, 0x00, 0x00, 0x00,
]), b[7:14].hex()
# shl rdi,cl — GAS: shl %cl,%rdi → 48 d3 e7
assert b[14:17] == bytes([0x48, 0xD3, 0xE7]), b[14:17].hex()
print("shiftcl bin OK", len(b), "bytes")
PY

objdump -d "$OUT/shiftcl.o" | grep -q shl

ld -o "$OUT/shiftcl" "$OUT/shiftcl.o"
set +e
"$OUT/shiftcl"
st=$?
set -e
test "$st" -eq 42

echo "test_shiftcl OK (shl reg,cl + exit 42)"
