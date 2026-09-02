#!/usr/bin/env bash
# bsr → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/bsr.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/bsr.o" "$FIX"
"$ASM" --format=bin -o "$OUT/bsr.bin" "$FIX"

python3 - "$OUT/bsr.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rsi,512
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC6, 0x00, 0x02, 0x00, 0x00,
]), b[0:7].hex()
# bsr rdi,rsi — GAS: bsr %rsi,%rdi → 48 0f bd fe
assert b[7:11] == bytes([0x48, 0x0F, 0xBD, 0xFE]), b[7:11].hex()
print("bsr bin OK", len(b), "bytes")
PY

objdump -d "$OUT/bsr.o" | grep -q bsr

ld -o "$OUT/bsr" "$OUT/bsr.o"
set +e
"$OUT/bsr"
st=$?
set -e
test "$st" -eq 42

echo "test_bsr OK (bsr + exit 42)"
