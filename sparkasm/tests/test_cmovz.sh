#!/usr/bin/env bash
# cmove/cmovz → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/cmovz.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/cmovz.o" "$FIX"
"$ASM" --format=bin -o "$OUT/cmovz.bin" "$FIX"

python3 - "$OUT/cmovz.bin" <<'PY'
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
# cmp rdi,rdi — GAS: cmp %rdi,%rdi → 48 39 ff
assert b[14:17] == bytes([0x48, 0x39, 0xFF]), b[14:17].hex()
# cmove rdi,rsi — GAS: cmove %rsi,%rdi → 48 0f 44 fe
assert b[17:21] == bytes([0x48, 0x0F, 0x44, 0xFE]), b[17:21].hex()
print("cmovz bin OK", len(b), "bytes")
PY

objdump -d "$OUT/cmovz.o" | grep -q cmove

ld -o "$OUT/cmovz" "$OUT/cmovz.o"
set +e
"$OUT/cmovz"
st=$?
set -e
test "$st" -eq 42

echo "test_cmovz OK (cmove + exit 42)"
