#!/usr/bin/env bash
# rcr → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/rcr.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/rcr.o" "$FIX"
"$ASM" --format=bin -o "$OUT/rcr.bin" "$FIX"

python3 - "$OUT/rcr.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,84
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC7, 0x54, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# clc — GAS: f8
assert b[7] == 0xF8, hex(b[7])
# rcr rdi,1 — GAS: rcr $1,%rdi → 48 d1 df
assert b[8:11] == bytes([0x48, 0xD1, 0xDF]), b[8:11].hex()
print("rcr bin OK", len(b), "bytes")
PY

objdump -d "$OUT/rcr.o" | grep -q rcr

ld -o "$OUT/rcr" "$OUT/rcr.o"
set +e
"$OUT/rcr"
st=$?
set -e
test "$st" -eq 42

echo "test_rcr OK (rcr + exit 42)"
