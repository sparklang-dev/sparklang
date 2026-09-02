#!/usr/bin/env bash
# bts → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/bts.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/bts.o" "$FIX"
"$ASM" --format=bin -o "$OUT/bts.bin" "$FIX"

python3 - "$OUT/bts.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rsi,0
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC6, 0x00, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# mov rcx,0
assert b[7:14] == bytes([
    0x48, 0xC7, 0xC1, 0x00, 0x00, 0x00, 0x00,
]), b[7:14].hex()
# bts rsi,rcx — GAS: bts %rcx,%rsi → 48 0f ab ce
assert b[14:18] == bytes([0x48, 0x0F, 0xAB, 0xCE]), b[14:18].hex()
print("bts bin OK", len(b), "bytes")
PY

objdump -d "$OUT/bts.o" | grep -q bts

ld -o "$OUT/bts" "$OUT/bts.o"
set +e
"$OUT/bts"
st=$?
set -e
test "$st" -eq 42

echo "test_bts OK (bts + exit 42)"
