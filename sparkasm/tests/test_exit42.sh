#!/usr/bin/env bash
# Assemble exit42.sasm → ELF .o → nm/objdump → ld → run (status 42)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/exit42.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/exit42.o" "$FIX"
"$ASM" --format=bin -o "$OUT/exit42.bin" "$FIX"

python3 - "$OUT/exit42.bin" <<'PY'
import pathlib, sys
b = pathlib.Path(sys.argv[1]).read_bytes()
expect = bytes([
    0x48, 0xC7, 0xC0, 0x3C, 0x00, 0x00, 0x00,
    0x48, 0xC7, 0xC7, 0x2A, 0x00, 0x00, 0x00,
    0x0F, 0x05,
])
assert b == expect, b.hex()
print("bin OK", len(b), "bytes")
PY

file "$OUT/exit42.o" | grep -q "relocatable"
nm "$OUT/exit42.o" | grep -E '[[:space:]]T[[:space:]]+_start$'
objdump -d "$OUT/exit42.o" | grep -q syscall

ld -o "$OUT/exit42" "$OUT/exit42.o"
set +e
"$OUT/exit42"
st=$?
set -e
test "$st" -eq 42

echo "test_exit42 OK (nm + objdump + linked exit 42)"
