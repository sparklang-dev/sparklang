#!/usr/bin/env bash
# cmovl → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/cmovl.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/cmovl.o" "$FIX"
"$ASM" --format=bin -o "$OUT/cmovl.bin" "$FIX"

python3 - "$OUT/cmovl.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,0
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC7, 0x00, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# mov rsi,42
assert b[7:14] == bytes([
    0x48, 0xC7, 0xC6, 0x2A, 0x00, 0x00, 0x00,
]), b[7:14].hex()
# mov rax,-1
assert b[14:21] == bytes([
    0x48, 0xC7, 0xC0, 0xFF, 0xFF, 0xFF, 0xFF,
]), b[14:21].hex()
# cmp rax,0
assert b[21:25] == bytes([0x48, 0x83, 0xF8, 0x00]), b[21:25].hex()
# cmovl rdi,rsi — GAS: cmovl %rsi,%rdi → 48 0f 4c fe
assert b[25:29] == bytes([0x48, 0x0F, 0x4C, 0xFE]), b[25:29].hex()
print("cmovl bin OK", len(b), "bytes")
PY

objdump -d "$OUT/cmovl.o" | grep -q cmovl

ld -o "$OUT/cmovl" "$OUT/cmovl.o"
set +e
"$OUT/cmovl"
st=$?
set -e
test "$st" -eq 42

echo "test_cmovl OK (cmovl + exit 42)"
