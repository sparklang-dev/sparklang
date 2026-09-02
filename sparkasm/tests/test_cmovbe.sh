#!/usr/bin/env bash
# cmovbe → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/cmovbe.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/cmovbe.o" "$FIX"
"$ASM" --format=bin -o "$OUT/cmovbe.bin" "$FIX"

python3 - "$OUT/cmovbe.bin" <<'PY'
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
# mov rax,1
assert b[14:21] == bytes([
    0x48, 0xC7, 0xC0, 0x01, 0x00, 0x00, 0x00,
]), b[14:21].hex()
# cmp rax,2
assert b[21:25] == bytes([0x48, 0x83, 0xF8, 0x02]), b[21:25].hex()
# cmovbe rdi,rsi — GAS: cmovbe %rsi,%rdi → 48 0f 46 fe
assert b[25:29] == bytes([0x48, 0x0F, 0x46, 0xFE]), b[25:29].hex()
print("cmovbe bin OK", len(b), "bytes")
PY

objdump -d "$OUT/cmovbe.o" | grep -q cmovbe

ld -o "$OUT/cmovbe" "$OUT/cmovbe.o"
set +e
"$OUT/cmovbe"
st=$?
set -e
test "$st" -eq 42

echo "test_cmovbe OK (cmovbe + exit 42)"
