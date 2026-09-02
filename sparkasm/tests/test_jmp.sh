#!/usr/bin/env bash
# near jmp forward → linked exit 42 + byte check
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/jmp.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/jmp.o" "$FIX"
"$ASM" --format=bin -o "$OUT/jmp.bin" "$FIX"

python3 - "$OUT/jmp.bin" <<'PY'
import pathlib, sys, struct
b = pathlib.Path(sys.argv[1]).read_bytes()
# jmp ok: E9 rel32; next_pc=5
# dead: mov rax 60 (7) + mov rdi 1 (7) + syscall (2) = 16
# ok @ 5+16 = 21
assert b[0] == 0xE9
rel = struct.unpack_from("<i", b, 1)[0]
assert 5 + rel == 21, (rel, 5 + rel)
dead = bytes([
    0x48, 0xC7, 0xC0, 0x3C, 0x00, 0x00, 0x00,
    0x48, 0xC7, 0xC7, 0x01, 0x00, 0x00, 0x00,
    0x0F, 0x05,
])
ok = bytes([
    0x48, 0xC7, 0xC0, 0x3C, 0x00, 0x00, 0x00,
    0x48, 0xC7, 0xC7, 0x2A, 0x00, 0x00, 0x00,
    0x0F, 0x05,
])
assert b[5:21] == dead, b[5:21].hex()
assert b[21:] == ok, b[21:].hex()
print("jmp bin OK", len(b), "bytes")
PY

objdump -d "$OUT/jmp.o" | grep -q jmp

ld -o "$OUT/jmp" "$OUT/jmp.o"
set +e
"$OUT/jmp"
st=$?
set -e
test "$st" -eq 42

echo "test_jmp OK (forward jmp + exit 42)"
