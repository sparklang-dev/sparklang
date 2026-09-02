#!/usr/bin/env bash
# test reg,imm → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/testimm.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/testimm.o" "$FIX"
"$ASM" --format=bin -o "$OUT/testimm.bin" "$FIX"

python3 - "$OUT/testimm.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,0
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC7, 0x00, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# test rdi,1 — GAS: testq $1,%rdi → 48 f7 c7 01 00 00 00
assert b[7:14] == bytes([
    0x48, 0xF7, 0xC7, 0x01, 0x00, 0x00, 0x00,
]), b[7:14].hex()
# jz exit42 — near 0F 84
assert b[14:16] == bytes([0x0F, 0x84]), b[14:16].hex()
print("testimm bin OK", len(b), "bytes")
PY

objdump -d "$OUT/testimm.o" | grep -q test

ld -o "$OUT/testimm" "$OUT/testimm.o"
set +e
"$OUT/testimm"
st=$?
set -e
test "$st" -eq 42

echo "test_testimm OK (test reg,imm + exit 42)"
