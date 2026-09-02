#!/usr/bin/env bash
# add/sub reg,reg → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/addsubrr.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/addsubrr.o" "$FIX"
"$ASM" --format=bin -o "$OUT/addsubrr.bin" "$FIX"

python3 - "$OUT/addsubrr.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,40
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC7, 0x28, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# mov rsi,5
assert b[7:14] == bytes([
    0x48, 0xC7, 0xC6, 0x05, 0x00, 0x00, 0x00,
]), b[7:14].hex()
# add rdi,rsi — GAS: add %rsi,%rdi → 48 01 f7
assert b[14:17] == bytes([0x48, 0x01, 0xF7]), b[14:17].hex()
# mov rsi,3
assert b[17:24] == bytes([
    0x48, 0xC7, 0xC6, 0x03, 0x00, 0x00, 0x00,
]), b[17:24].hex()
# sub rdi,rsi — GAS: sub %rsi,%rdi → 48 29 f7
assert b[24:27] == bytes([0x48, 0x29, 0xF7]), b[24:27].hex()
# mov rax,60 + syscall
assert b[27:34] == bytes([
    0x48, 0xC7, 0xC0, 0x3C, 0x00, 0x00, 0x00,
]), b[27:34].hex()
assert b[34:36] == bytes([0x0F, 0x05]), b[34:36].hex()
print("addsubrr bin OK", len(b), "bytes")
PY

objdump -d "$OUT/addsubrr.o" | grep -q add
objdump -d "$OUT/addsubrr.o" | grep -q sub

ld -o "$OUT/addsubrr" "$OUT/addsubrr.o"
set +e
"$OUT/addsubrr"
st=$?
set -e
test "$st" -eq 42

echo "test_addsubrr OK (add/sub reg,reg + exit 42)"
