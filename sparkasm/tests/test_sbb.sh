#!/usr/bin/env bash
# sbb reg,reg → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/sbb.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/sbb.o" "$FIX"
"$ASM" --format=bin -o "$OUT/sbb.bin" "$FIX"

python3 - "$OUT/sbb.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,43
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC7, 0x2B, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# mov rsi,1
assert b[7:14] == bytes([
    0x48, 0xC7, 0xC6, 0x01, 0x00, 0x00, 0x00,
]), b[7:14].hex()
# sbb rdi,rsi — GAS: sbb %rsi,%rdi → 48 19 f7
assert b[14:17] == bytes([0x48, 0x19, 0xF7]), b[14:17].hex()
print("sbb bin OK", len(b), "bytes")
PY

objdump -d "$OUT/sbb.o" | grep -q sbb

ld -o "$OUT/sbb" "$OUT/sbb.o"
set +e
"$OUT/sbb"
st=$?
set -e
test "$st" -eq 42

echo "test_sbb OK (sbb reg,reg + exit 42)"
