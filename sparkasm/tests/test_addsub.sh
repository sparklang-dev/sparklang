#!/usr/bin/env bash
# add/sub reg,imm → linked exit 42
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/addsub.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/addsub.o" "$FIX"
"$ASM" --format=bin -o "$OUT/addsub.bin" "$FIX"

python3 - "$OUT/addsub.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,40
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC7, 0x28, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# add rdi,5 — 48 83 /0 C7 05
assert b[7:11] == bytes([0x48, 0x83, 0xC7, 0x05]), b[7:11].hex()
# sub rdi,3 — 48 83 /5 EF 03
assert b[11:15] == bytes([0x48, 0x83, 0xEF, 0x03]), b[11:15].hex()
# mov rax,60 + syscall
assert b[15:22] == bytes([
    0x48, 0xC7, 0xC0, 0x3C, 0x00, 0x00, 0x00,
]), b[15:22].hex()
assert b[22:24] == bytes([0x0F, 0x05]), b[22:24].hex()
print("addsub bin OK", len(b), "bytes")
PY

objdump -d "$OUT/addsub.o" | grep -q add
objdump -d "$OUT/addsub.o" | grep -q sub

ld -o "$OUT/addsub" "$OUT/addsub.o"
set +e
"$OUT/addsub"
st=$?
set -e
test "$st" -eq 42

echo "test_addsub OK (add/sub imm + exit 42)"
