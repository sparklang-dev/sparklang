#!/usr/bin/env bash
# shrd → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/shrd.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/shrd.o" "$FIX"
"$ASM" --format=bin -o "$OUT/shrd.bin" "$FIX"

python3 - "$OUT/shrd.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,84
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC7, 0x54, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# mov rsi,0
assert b[7:14] == bytes([
    0x48, 0xC7, 0xC6, 0x00, 0x00, 0x00, 0x00,
]), b[7:14].hex()
# shrd rdi,rsi,1 — GAS: shrd $1,%rsi,%rdi → 48 0f ac f7 01
assert b[14:19] == bytes([
    0x48, 0x0F, 0xAC, 0xF7, 0x01,
]), b[14:19].hex()
print("shrd bin OK", len(b), "bytes")
PY

objdump -d "$OUT/shrd.o" | grep -q shrd

ld -o "$OUT/shrd" "$OUT/shrd.o"
set +e
"$OUT/shrd"
st=$?
set -e
test "$st" -eq 42

echo "test_shrd OK (shrd + exit 42)"
