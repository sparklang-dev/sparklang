#!/usr/bin/env bash
# std → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/std.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/std.o" "$FIX"
"$ASM" --format=bin -o "$OUT/std.bin" "$FIX"

python3 - "$OUT/std.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,42
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC7, 0x2A, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# std — GAS: fd
assert b[7] == 0xFD, hex(b[7])
print("std bin OK", len(b), "bytes")
PY

objdump -d "$OUT/std.o" | grep -q std

ld -o "$OUT/std" "$OUT/std.o"
set +e
"$OUT/std"
st=$?
set -e
test "$st" -eq 42

echo "test_std OK (std + exit 42)"
