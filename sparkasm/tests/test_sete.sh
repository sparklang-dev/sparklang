#!/usr/bin/env bash
# sete al → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/sete.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/sete.o" "$FIX"
"$ASM" --format=bin -o "$OUT/sete.bin" "$FIX"

python3 - "$OUT/sete.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# xor rax,rax — GAS: xor %rax,%rax → 48 31 c0
assert b[0:3] == bytes([0x48, 0x31, 0xC0]), b[0:3].hex()
# mov rsi,5
assert b[3:10] == bytes([
    0x48, 0xC7, 0xC6, 0x05, 0x00, 0x00, 0x00,
]), b[3:10].hex()
# mov rdi,5
assert b[10:17] == bytes([
    0x48, 0xC7, 0xC7, 0x05, 0x00, 0x00, 0x00,
]), b[10:17].hex()
# cmp rdi,rsi — 48 39 f7
assert b[17:20] == bytes([0x48, 0x39, 0xF7]), b[17:20].hex()
# sete al — GAS: sete %al → 0f 94 c0
assert b[20:23] == bytes([0x0F, 0x94, 0xC0]), b[20:23].hex()
# add rax,41
assert b[23:27] == bytes([0x48, 0x83, 0xC0, 0x29]), b[23:27].hex()
print("sete bin OK", len(b), "bytes")
PY

objdump -d "$OUT/sete.o" | grep -Eq 'sete|setz'

ld -o "$OUT/sete" "$OUT/sete.o"
set +e
"$OUT/sete"
st=$?
set -e
test "$st" -eq 42

echo "test_sete OK (sete al + exit 42)"
