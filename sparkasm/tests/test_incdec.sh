#!/usr/bin/env bash
# inc/dec reg → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/incdec.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/incdec.o" "$FIX"
"$ASM" --format=bin -o "$OUT/incdec.bin" "$FIX"

python3 - "$OUT/incdec.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,42
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC7, 0x2A, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# inc rdi — GAS: inc %rdi → 48 ff c7
assert b[7:10] == bytes([0x48, 0xFF, 0xC7]), b[7:10].hex()
# dec rdi — GAS: dec %rdi → 48 ff cf
assert b[10:13] == bytes([0x48, 0xFF, 0xCF]), b[10:13].hex()
# mov rax,60 + syscall
assert b[13:20] == bytes([
    0x48, 0xC7, 0xC0, 0x3C, 0x00, 0x00, 0x00,
]), b[13:20].hex()
assert b[20:22] == bytes([0x0F, 0x05]), b[20:22].hex()
print("incdec bin OK", len(b), "bytes")
PY

objdump -d "$OUT/incdec.o" | grep -q 'inc.*%rdi\|inc.*rdi'
objdump -d "$OUT/incdec.o" | grep -q 'dec.*%rdi\|dec.*rdi'

ld -o "$OUT/incdec" "$OUT/incdec.o"
set +e
"$OUT/incdec"
st=$?
set -e
test "$st" -eq 42

echo "test_incdec OK (inc/dec reg + exit 42)"
