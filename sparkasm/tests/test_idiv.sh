#!/usr/bin/env bash
# idiv → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/idiv.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/idiv.o" "$FIX"
"$ASM" --format=bin -o "$OUT/idiv.bin" "$FIX"

python3 - "$OUT/idiv.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rax,84
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC0, 0x54, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# cqo
assert b[7:9] == bytes([0x48, 0x99]), b[7:9].hex()
# mov rsi,2
assert b[9:16] == bytes([
    0x48, 0xC7, 0xC6, 0x02, 0x00, 0x00, 0x00,
]), b[9:16].hex()
# idiv rsi — GAS: idiv %rsi → 48 f7 fe
assert b[16:19] == bytes([0x48, 0xF7, 0xFE]), b[16:19].hex()
print("idiv bin OK", len(b), "bytes")
PY

objdump -d "$OUT/idiv.o" | grep -q idiv

ld -o "$OUT/idiv" "$OUT/idiv.o"
set +e
"$OUT/idiv"
st=$?
set -e
test "$st" -eq 42

echo "test_idiv OK (idiv + exit 42)"
