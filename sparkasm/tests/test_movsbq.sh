#!/usr/bin/env bash
# movsbq → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/movsbq.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/movsbq.o" "$FIX"
"$ASM" --format=bin -o "$OUT/movsbq.bin" "$FIX"

python3 - "$OUT/movsbq.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rax,-1
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC0, 0xFF, 0xFF, 0xFF, 0xFF,
]), b[0:7].hex()
# movsbq rdi,al — GAS: movsbq %al,%rdi → 48 0f be f8
assert b[7:11] == bytes([0x48, 0x0F, 0xBE, 0xF8]), b[7:11].hex()
# add rdi,43
assert b[11:15] == bytes([0x48, 0x83, 0xC7, 0x2B]), b[11:15].hex()
print("movsbq bin OK", len(b), "bytes")
PY

objdump -d "$OUT/movsbq.o" | grep -Eq 'movs'

ld -o "$OUT/movsbq" "$OUT/movsbq.o"
set +e
"$OUT/movsbq"
st=$?
set -e
test "$st" -eq 42

echo "test_movsbq OK (movsbq + exit 42)"
