#!/usr/bin/env bash
# movzbq → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/movzbq.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/movzbq.o" "$FIX"
"$ASM" --format=bin -o "$OUT/movzbq.bin" "$FIX"

python3 - "$OUT/movzbq.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# xor + movs + cmp + sete = 23 bytes (same as sete fixture start)
assert b[0:3] == bytes([0x48, 0x31, 0xC0]), b[0:3].hex()
assert b[20:23] == bytes([0x0F, 0x94, 0xC0]), b[20:23].hex()
# movzbq rdi,al — GAS: movzbq %al,%rdi → 48 0f b6 f8
assert b[23:27] == bytes([0x48, 0x0F, 0xB6, 0xF8]), b[23:27].hex()
# add rdi,41
assert b[27:31] == bytes([0x48, 0x83, 0xC7, 0x29]), b[27:31].hex()
print("movzbq bin OK", len(b), "bytes")
PY

objdump -d "$OUT/movzbq.o" | grep -Eq 'movz'

ld -o "$OUT/movzbq" "$OUT/movzbq.o"
set +e
"$OUT/movzbq"
st=$?
set -e
test "$st" -eq 42

echo "test_movzbq OK (movzbq + exit 42)"
