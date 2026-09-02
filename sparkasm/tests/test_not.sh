#!/usr/bin/env bash
# not reg → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/not.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/not.o" "$FIX"
"$ASM" --format=bin -o "$OUT/not.bin" "$FIX"

python3 - "$OUT/not.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,-43
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC7, 0xD5, 0xFF, 0xFF, 0xFF,
]), b[0:7].hex()
# not rdi — GAS: not %rdi → 48 f7 d7
assert b[7:10] == bytes([0x48, 0xF7, 0xD7]), b[7:10].hex()
# mov rax,60 + syscall
assert b[10:17] == bytes([
    0x48, 0xC7, 0xC0, 0x3C, 0x00, 0x00, 0x00,
]), b[10:17].hex()
assert b[17:19] == bytes([0x0F, 0x05]), b[17:19].hex()
print("not bin OK", len(b), "bytes")
PY

objdump -d "$OUT/not.o" | grep -q not

ld -o "$OUT/not" "$OUT/not.o"
set +e
"$OUT/not"
st=$?
set -e
test "$st" -eq 42

echo "test_not OK (not reg + exit 42)"
