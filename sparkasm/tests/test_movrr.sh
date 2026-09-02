#!/usr/bin/env bash
# mov reg,reg → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/movrr.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/movrr.o" "$FIX"
"$ASM" --format=bin -o "$OUT/movrr.bin" "$FIX"

python3 - "$OUT/movrr.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rsi,42
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC6, 0x2A, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# mov rdi,rsi — GAS: mov %rsi,%rdi → 48 89 f7
assert b[7:10] == bytes([0x48, 0x89, 0xF7]), b[7:10].hex()
# mov rax,60 + syscall
assert b[10:17] == bytes([
    0x48, 0xC7, 0xC0, 0x3C, 0x00, 0x00, 0x00,
]), b[10:17].hex()
assert b[17:19] == bytes([0x0F, 0x05]), b[17:19].hex()
print("movrr bin OK", len(b), "bytes")
PY

objdump -d "$OUT/movrr.o" | grep -q 'mov.*%rsi,%rdi\|mov.*rsi'

ld -o "$OUT/movrr" "$OUT/movrr.o"
set +e
"$OUT/movrr"
st=$?
set -e
test "$st" -eq 42

echo "test_movrr OK (mov reg,reg + exit 42)"
