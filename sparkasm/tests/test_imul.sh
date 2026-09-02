#!/usr/bin/env bash
# imul reg,imm → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/imul.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/imul.o" "$FIX"
"$ASM" --format=bin -o "$OUT/imul.bin" "$FIX"

python3 - "$OUT/imul.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,21
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC7, 0x15, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# imul rdi,2 — GAS: imul $2,%rdi → 48 6b ff 02
assert b[7:11] == bytes([0x48, 0x6B, 0xFF, 0x02]), b[7:11].hex()
# mov rax,60 + syscall
assert b[11:18] == bytes([
    0x48, 0xC7, 0xC0, 0x3C, 0x00, 0x00, 0x00,
]), b[11:18].hex()
assert b[18:20] == bytes([0x0F, 0x05]), b[18:20].hex()
print("imul bin OK", len(b), "bytes")
PY

objdump -d "$OUT/imul.o" | grep -q imul

ld -o "$OUT/imul" "$OUT/imul.o"
set +e
"$OUT/imul"
st=$?
set -e
test "$st" -eq 42

echo "test_imul OK (imul reg,imm + exit 42)"
