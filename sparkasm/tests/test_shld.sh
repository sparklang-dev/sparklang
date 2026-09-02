#!/usr/bin/env bash
# shld → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/shld.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/shld.o" "$FIX"
"$ASM" --format=bin -o "$OUT/shld.bin" "$FIX"

python3 - "$OUT/shld.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,21
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC7, 0x15, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# mov rsi,0
assert b[7:14] == bytes([
    0x48, 0xC7, 0xC6, 0x00, 0x00, 0x00, 0x00,
]), b[7:14].hex()
# shld rdi,rsi,1 — GAS: shld $1,%rsi,%rdi → 48 0f a4 f7 01
assert b[14:19] == bytes([
    0x48, 0x0F, 0xA4, 0xF7, 0x01,
]), b[14:19].hex()
print("shld bin OK", len(b), "bytes")
PY

objdump -d "$OUT/shld.o" | grep -q shld

ld -o "$OUT/shld" "$OUT/shld.o"
set +e
"$OUT/shld"
st=$?
set -e
test "$st" -eq 42

echo "test_shld OK (shld + exit 42)"
