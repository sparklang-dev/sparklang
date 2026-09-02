#!/usr/bin/env bash
# shl/shr reg,imm → linked exit 42
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/shift.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/shift.o" "$FIX"
"$ASM" --format=bin -o "$OUT/shift.bin" "$FIX"

python3 - "$OUT/shift.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,21
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC7, 0x15, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# shl rdi,1 — 48 D1 /4 E7
assert b[7:10] == bytes([0x48, 0xD1, 0xE7]), b[7:10].hex()
# mov rsi,168
assert b[10:17] == bytes([
    0x48, 0xC7, 0xC6, 0xA8, 0x00, 0x00, 0x00,
]), b[10:17].hex()
# shr rsi,2 — 48 C1 /5 EE 02
assert b[17:21] == bytes([0x48, 0xC1, 0xEE, 0x02]), b[17:21].hex()
# mov rax,60 + syscall
assert b[21:28] == bytes([
    0x48, 0xC7, 0xC0, 0x3C, 0x00, 0x00, 0x00,
]), b[21:28].hex()
assert b[28:30] == bytes([0x0F, 0x05]), b[28:30].hex()
print("shift bin OK", len(b), "bytes")
PY

objdump -d "$OUT/shift.o" | grep -q shl
objdump -d "$OUT/shift.o" | grep -q shr

ld -o "$OUT/shift" "$OUT/shift.o"
set +e
"$OUT/shift"
st=$?
set -e
test "$st" -eq 42

echo "test_shift OK (shl/shr imm + exit 42)"
