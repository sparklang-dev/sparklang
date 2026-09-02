#!/usr/bin/env bash
# cmovae → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/cmovae.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/cmovae.o" "$FIX"
"$ASM" --format=bin -o "$OUT/cmovae.bin" "$FIX"

python3 - "$OUT/cmovae.bin" <<'PY'
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
# mov rax,2
assert b[14:21] == bytes([
    0x48, 0xC7, 0xC0, 0x02, 0x00, 0x00, 0x00,
]), b[14:21].hex()
# cmp rax,1
assert b[21:25] == bytes([0x48, 0x83, 0xF8, 0x01]), b[21:25].hex()
# cmovae rdi,rsi — GAS: cmovae %rsi,%rdi → 48 0f 43 fe
assert b[25:29] == bytes([0x48, 0x0F, 0x43, 0xFE]), b[25:29].hex()
print("cmovae bin OK", len(b), "bytes")
PY

objdump -d "$OUT/cmovae.o" | grep -q cmovae

ld -o "$OUT/cmovae" "$OUT/cmovae.o"
set +e
"$OUT/cmovae"
st=$?
set -e
test "$st" -eq 42

echo "test_cmovae OK (cmovae + exit 42)"
