#!/usr/bin/env bash
# mul → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/mul.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/mul.o" "$FIX"
"$ASM" --format=bin -o "$OUT/mul.bin" "$FIX"

python3 - "$OUT/mul.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rax,21
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC0, 0x15, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# mov rsi,2
assert b[7:14] == bytes([
    0x48, 0xC7, 0xC6, 0x02, 0x00, 0x00, 0x00,
]), b[7:14].hex()
# mul rsi — GAS: mul %rsi → 48 f7 e6
assert b[14:17] == bytes([0x48, 0xF7, 0xE6]), b[14:17].hex()
print("mul bin OK", len(b), "bytes")
PY

objdump -d "$OUT/mul.o" | grep -q mul

ld -o "$OUT/mul" "$OUT/mul.o"
set +e
"$OUT/mul"
st=$?
set -e
test "$st" -eq 42

echo "test_mul OK (mul + exit 42)"
