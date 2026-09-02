#!/usr/bin/env bash
# std/cld → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/cld.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/cld.o" "$FIX"
"$ASM" --format=bin -o "$OUT/cld.bin" "$FIX"

python3 - "$OUT/cld.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,42
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC7, 0x2A, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# std — GAS: fd
assert b[7] == 0xFD, hex(b[7])
# cld — GAS: fc
assert b[8] == 0xFC, hex(b[8])
print("cld bin OK", len(b), "bytes")
PY

objdump -d "$OUT/cld.o" | grep -q cld

ld -o "$OUT/cld" "$OUT/cld.o"
set +e
"$OUT/cld"
st=$?
set -e
test "$st" -eq 42

echo "test_cld OK (std/cld + exit 42)"
