#!/usr/bin/env bash
# lea [reg+disp] / [reg+reg] → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/lea.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/lea.o" "$FIX"
"$ASM" --format=bin -o "$OUT/lea.bin" "$FIX"

python3 - "$OUT/lea.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rsi,40
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC6, 0x28, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# lea rdi,[rsi+2] — GAS: 48 8d 7e 02
assert b[7:11] == bytes([0x48, 0x8D, 0x7E, 0x02]), b[7:11].hex()
# mov rax,42
assert b[11:18] == bytes([
    0x48, 0xC7, 0xC0, 0x2A, 0x00, 0x00, 0x00,
]), b[11:18].hex()
# mov rcx,0
assert b[18:25] == bytes([
    0x48, 0xC7, 0xC1, 0x00, 0x00, 0x00, 0x00,
]), b[18:25].hex()
# lea rdi,[rax+rcx] — GAS: 48 8d 3c 08
assert b[25:29] == bytes([0x48, 0x8D, 0x3C, 0x08]), b[25:29].hex()
# mov rax,60 + syscall
assert b[29:36] == bytes([
    0x48, 0xC7, 0xC0, 0x3C, 0x00, 0x00, 0x00,
]), b[29:36].hex()
assert b[36:38] == bytes([0x0F, 0x05]), b[36:38].hex()
print("lea bin OK", len(b), "bytes")
PY

objdump -d "$OUT/lea.o" | grep -q 'lea'

ld -o "$OUT/lea" "$OUT/lea.o"
set +e
"$OUT/lea"
st=$?
set -e
test "$st" -eq 42

echo "test_lea OK (lea base+disp + base+index + exit 42)"
