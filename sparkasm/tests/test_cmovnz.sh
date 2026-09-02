#!/usr/bin/env bash
# cmovne/cmovnz → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/cmovnz.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/cmovnz.o" "$FIX"
"$ASM" --format=bin -o "$OUT/cmovnz.bin" "$FIX"

python3 - "$OUT/cmovnz.bin" <<'PY'
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
# cmp rax,0 — 48 83 f8 00
assert b[21:25] == bytes([0x48, 0x83, 0xF8, 0x00]), b[21:25].hex()
# cmovne rdi,rsi — GAS: cmovne %rsi,%rdi → 48 0f 45 fe
assert b[25:29] == bytes([0x48, 0x0F, 0x45, 0xFE]), b[25:29].hex()
print("cmovnz bin OK", len(b), "bytes")
PY

objdump -d "$OUT/cmovnz.o" | grep -q cmovne

ld -o "$OUT/cmovnz" "$OUT/cmovnz.o"
set +e
"$OUT/cmovnz"
st=$?
set -e
test "$st" -eq 42

echo "test_cmovnz OK (cmovne + exit 42)"
