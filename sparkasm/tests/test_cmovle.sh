#!/usr/bin/env bash
# cmovle → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/cmovle.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/cmovle.o" "$FIX"
"$ASM" --format=bin -o "$OUT/cmovle.bin" "$FIX"

python3 - "$OUT/cmovle.bin" <<'PY'
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
# mov rax,0
assert b[14:21] == bytes([
    0x48, 0xC7, 0xC0, 0x00, 0x00, 0x00, 0x00,
]), b[14:21].hex()
# cmp rax,0
assert b[21:25] == bytes([0x48, 0x83, 0xF8, 0x00]), b[21:25].hex()
# cmovle rdi,rsi — GAS: cmovle %rsi,%rdi → 48 0f 4e fe
assert b[25:29] == bytes([0x48, 0x0F, 0x4E, 0xFE]), b[25:29].hex()
print("cmovle bin OK", len(b), "bytes")
PY

objdump -d "$OUT/cmovle.o" | grep -q cmovle

ld -o "$OUT/cmovle" "$OUT/cmovle.o"
set +e
"$OUT/cmovle"
st=$?
set -e
test "$st" -eq 42

echo "test_cmovle OK (cmovle + exit 42)"
