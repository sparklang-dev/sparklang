#!/usr/bin/env bash
# xchg reg,reg → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/xchg.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/xchg.o" "$FIX"
"$ASM" --format=bin -o "$OUT/xchg.bin" "$FIX"

python3 - "$OUT/xchg.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rsi,42
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC6, 0x2A, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# mov rdi,0
assert b[7:14] == bytes([
    0x48, 0xC7, 0xC7, 0x00, 0x00, 0x00, 0x00,
]), b[7:14].hex()
# xchg rsi,rdi — GAS: xchg %rsi,%rdi → 48 87 f7
assert b[14:17] == bytes([0x48, 0x87, 0xF7]), b[14:17].hex()
# mov rax,60 + syscall
assert b[17:24] == bytes([
    0x48, 0xC7, 0xC0, 0x3C, 0x00, 0x00, 0x00,
]), b[17:24].hex()
assert b[24:26] == bytes([0x0F, 0x05]), b[24:26].hex()
print("xchg bin OK", len(b), "bytes")
PY

objdump -d "$OUT/xchg.o" | grep -q xchg

ld -o "$OUT/xchg" "$OUT/xchg.o"
set +e
"$OUT/xchg"
st=$?
set -e
test "$st" -eq 42

echo "test_xchg OK (xchg reg,reg + exit 42)"
