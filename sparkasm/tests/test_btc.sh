#!/usr/bin/env bash
# btc → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/btc.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/btc.o" "$FIX"
"$ASM" --format=bin -o "$OUT/btc.bin" "$FIX"

python3 - "$OUT/btc.bin" <<'PY'
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
# btc rsi,rcx — GAS: btc %rcx,%rsi → 48 0f bb ce
assert b[14:18] == bytes([0x48, 0x0F, 0xBB, 0xCE]), b[14:18].hex()
print("btc bin OK", len(b), "bytes")
PY

objdump -d "$OUT/btc.o" | grep -q btc

ld -o "$OUT/btc" "$OUT/btc.o"
set +e
"$OUT/btc"
st=$?
set -e
test "$st" -eq 42

echo "test_btc OK (btc + exit 42)"
