#!/usr/bin/env bash
# cmovge → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/cmovge.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/cmovge.o" "$FIX"
"$ASM" --format=bin -o "$OUT/cmovge.bin" "$FIX"

python3 - "$OUT/cmovge.bin" <<'PY'
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
# cmovge rdi,rsi — GAS: cmovge %rsi,%rdi → 48 0f 4d fe
assert b[25:29] == bytes([0x48, 0x0F, 0x4D, 0xFE]), b[25:29].hex()
print("cmovge bin OK", len(b), "bytes")
PY

objdump -d "$OUT/cmovge.o" | grep -q cmovge

ld -o "$OUT/cmovge" "$OUT/cmovge.o"
set +e
"$OUT/cmovge"
st=$?
set -e
test "$st" -eq 42

echo "test_cmovge OK (cmovge + exit 42)"
