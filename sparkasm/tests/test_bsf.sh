#!/usr/bin/env bash
# bsf → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/bsf.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/bsf.o" "$FIX"
"$ASM" --format=bin -o "$OUT/bsf.bin" "$FIX"

python3 - "$OUT/bsf.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rsi,256
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC6, 0x00, 0x01, 0x00, 0x00,
]), b[0:7].hex()
# bsf rdi,rsi — GAS: bsf %rsi,%rdi → 48 0f bc fe
assert b[7:11] == bytes([0x48, 0x0F, 0xBC, 0xFE]), b[7:11].hex()
print("bsf bin OK", len(b), "bytes")
PY

objdump -d "$OUT/bsf.o" | grep -q bsf

ld -o "$OUT/bsf" "$OUT/bsf.o"
set +e
"$OUT/bsf"
st=$?
set -e
test "$st" -eq 42

echo "test_bsf OK (bsf + exit 42)"
