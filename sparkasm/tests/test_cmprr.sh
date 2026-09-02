#!/usr/bin/env bash
# cmp reg,reg → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/cmprr.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/cmprr.o" "$FIX"
"$ASM" --format=bin -o "$OUT/cmprr.bin" "$FIX"

python3 - "$OUT/cmprr.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,5
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC7, 0x05, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# mov rsi,5
assert b[7:14] == bytes([
    0x48, 0xC7, 0xC6, 0x05, 0x00, 0x00, 0x00,
]), b[7:14].hex()
# cmp rdi,rsi — GAS: cmp %rsi,%rdi → 48 39 f7
assert b[14:17] == bytes([0x48, 0x39, 0xF7]), b[14:17].hex()
# je exit42 — near 0F 84 rel32
assert b[17:19] == bytes([0x0F, 0x84]), b[17:19].hex()
print("cmprr bin OK", len(b), "bytes")
PY

objdump -d "$OUT/cmprr.o" | grep -q cmp

ld -o "$OUT/cmprr" "$OUT/cmprr.o"
set +e
"$OUT/cmprr"
st=$?
set -e
test "$st" -eq 42

echo "test_cmprr OK (cmp reg,reg + exit 42)"
