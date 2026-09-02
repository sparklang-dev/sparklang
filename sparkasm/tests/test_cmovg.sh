#!/usr/bin/env bash
# cmovg → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/cmovg.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/cmovg.o" "$FIX"
"$ASM" --format=bin -o "$OUT/cmovg.bin" "$FIX"

python3 - "$OUT/cmovg.bin" <<'PY'
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
# cmp rax,0
assert b[21:25] == bytes([0x48, 0x83, 0xF8, 0x00]), b[21:25].hex()
# cmovg rdi,rsi — GAS: cmovg %rsi,%rdi → 48 0f 4f fe
assert b[25:29] == bytes([0x48, 0x0F, 0x4F, 0xFE]), b[25:29].hex()
print("cmovg bin OK", len(b), "bytes")
PY

objdump -d "$OUT/cmovg.o" | grep -q cmovg

ld -o "$OUT/cmovg" "$OUT/cmovg.o"
set +e
"$OUT/cmovg"
st=$?
set -e
test "$st" -eq 42

echo "test_cmovg OK (cmovg + exit 42)"
