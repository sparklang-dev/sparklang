#!/usr/bin/env bash
# bt → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/bt.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/bt.o" "$FIX"
"$ASM" --format=bin -o "$OUT/bt.bin" "$FIX"

python3 - "$OUT/bt.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,41
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC7, 0x29, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# mov rax,0
assert b[7:14] == bytes([
    0x48, 0xC7, 0xC0, 0x00, 0x00, 0x00, 0x00,
]), b[7:14].hex()
# mov rsi,2
assert b[14:21] == bytes([
    0x48, 0xC7, 0xC6, 0x02, 0x00, 0x00, 0x00,
]), b[14:21].hex()
# mov rcx,1
assert b[21:28] == bytes([
    0x48, 0xC7, 0xC1, 0x01, 0x00, 0x00, 0x00,
]), b[21:28].hex()
# bt rsi,rcx — GAS: bt %rcx,%rsi → 48 0f a3 ce
assert b[28:32] == bytes([0x48, 0x0F, 0xA3, 0xCE]), b[28:32].hex()
print("bt bin OK", len(b), "bytes")
PY

objdump -d "$OUT/bt.o" | grep -q bt

ld -o "$OUT/bt" "$OUT/bt.o"
set +e
"$OUT/bt"
st=$?
set -e
test "$st" -eq 42

echo "test_bt OK (bt + adc + exit 42)"
