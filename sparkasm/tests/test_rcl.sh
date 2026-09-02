#!/usr/bin/env bash
# rcl → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/rcl.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/rcl.o" "$FIX"
"$ASM" --format=bin -o "$OUT/rcl.bin" "$FIX"

python3 - "$OUT/rcl.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,21
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC7, 0x15, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# clc — GAS: f8
assert b[7] == 0xF8, hex(b[7])
# rcl rdi,1 — GAS: rcl $1,%rdi → 48 d1 d7
assert b[8:11] == bytes([0x48, 0xD1, 0xD7]), b[8:11].hex()
print("rcl bin OK", len(b), "bytes")
PY

objdump -d "$OUT/rcl.o" | grep -q rcl

ld -o "$OUT/rcl" "$OUT/rcl.o"
set +e
"$OUT/rcl"
st=$?
set -e
test "$st" -eq 42

echo "test_rcl OK (rcl + exit 42)"
