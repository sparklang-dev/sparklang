#!/usr/bin/env bash
# setl al → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/setl.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/setl.o" "$FIX"
"$ASM" --format=bin -o "$OUT/setl.bin" "$FIX"

python3 - "$OUT/setl.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# xor rax,rax
assert b[0:3] == bytes([0x48, 0x31, 0xC0]), b[0:3].hex()
# mov rdi,3
assert b[3:10] == bytes([
    0x48, 0xC7, 0xC7, 0x03, 0x00, 0x00, 0x00,
]), b[3:10].hex()
# mov rsi,5
assert b[10:17] == bytes([
    0x48, 0xC7, 0xC6, 0x05, 0x00, 0x00, 0x00,
]), b[10:17].hex()
# cmp rdi,rsi
assert b[17:20] == bytes([0x48, 0x39, 0xF7]), b[17:20].hex()
# setl al — GAS: setl %al → 0f 9c c0
assert b[20:23] == bytes([0x0F, 0x9C, 0xC0]), b[20:23].hex()
print("setl bin OK", len(b), "bytes")
PY

objdump -d "$OUT/setl.o" | grep -Eq 'setl|setnge'

ld -o "$OUT/setl" "$OUT/setl.o"
set +e
"$OUT/setl"
st=$?
set -e
test "$st" -eq 42

echo "test_setl OK (setl al + exit 42)"
