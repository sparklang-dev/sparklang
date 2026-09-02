#!/usr/bin/env bash
# neg reg → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/neg.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/neg.o" "$FIX"
"$ASM" --format=bin -o "$OUT/neg.bin" "$FIX"

python3 - "$OUT/neg.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,-42
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC7, 0xD6, 0xFF, 0xFF, 0xFF,
]), b[0:7].hex()
# neg rdi — GAS: neg %rdi → 48 f7 df
assert b[7:10] == bytes([0x48, 0xF7, 0xDF]), b[7:10].hex()
# mov rax,60 + syscall
assert b[10:17] == bytes([
    0x48, 0xC7, 0xC0, 0x3C, 0x00, 0x00, 0x00,
]), b[10:17].hex()
assert b[17:19] == bytes([0x0F, 0x05]), b[17:19].hex()
print("neg bin OK", len(b), "bytes")
PY

objdump -d "$OUT/neg.o" | grep -q neg

ld -o "$OUT/neg" "$OUT/neg.o"
set +e
"$OUT/neg"
st=$?
set -e
test "$st" -eq 42

echo "test_neg OK (neg reg + exit 42)"
