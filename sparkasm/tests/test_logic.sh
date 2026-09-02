#!/usr/bin/env bash
# and/or/xor reg,imm + reg,reg → linked exit 42
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/logic.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/logic.o" "$FIX"
"$ASM" --format=bin -o "$OUT/logic.bin" "$FIX"

python3 - "$OUT/logic.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,40
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC7, 0x28, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# or rdi,2 — 48 83 /1 CF 02
assert b[7:11] == bytes([0x48, 0x83, 0xCF, 0x02]), b[7:11].hex()
# mov rsi,255
assert b[11:18] == bytes([
    0x48, 0xC7, 0xC6, 0xFF, 0x00, 0x00, 0x00,
]), b[11:18].hex()
# and rdi,rsi — 48 21 /r F7
assert b[18:21] == bytes([0x48, 0x21, 0xF7]), b[18:21].hex()
# xor rcx,rcx — 48 31 /r C9
assert b[21:24] == bytes([0x48, 0x31, 0xC9]), b[21:24].hex()
# xor rdi,rcx — 48 31 /r CF
assert b[24:27] == bytes([0x48, 0x31, 0xCF]), b[24:27].hex()
# mov rax,60 + syscall
assert b[27:34] == bytes([
    0x48, 0xC7, 0xC0, 0x3C, 0x00, 0x00, 0x00,
]), b[27:34].hex()
assert b[34:36] == bytes([0x0F, 0x05]), b[34:36].hex()
print("logic bin OK", len(b), "bytes")
PY

objdump -d "$OUT/logic.o" | grep -q or
objdump -d "$OUT/logic.o" | grep -q and
objdump -d "$OUT/logic.o" | grep -q xor

ld -o "$OUT/logic" "$OUT/logic.o"
set +e
"$OUT/logic"
st=$?
set -e
test "$st" -eq 42

echo "test_logic OK (and/or/xor + exit 42)"
