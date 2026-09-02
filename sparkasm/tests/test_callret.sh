#!/usr/bin/env bash
# call/ret/push/pop → linked exit 42 + byte check
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/callret.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/callret.o" "$FIX"
"$ASM" --format=bin -o "$OUT/callret.bin" "$FIX"

python3 - "$OUT/callret.bin" <<'PY'
import pathlib, sys, struct
b = pathlib.Path(sys.argv[1]).read_bytes()
# call set_exit (E8 rel32); next_pc=5; set_exit at 5+7+2=14?
# _start: call(5) + mov rax 60 (7) + syscall (2) = 14
# set_exit @ 14: push rax(1) + mov rdi 42(7) + pop rax(1) + ret(1)
assert b[0] == 0xE8
rel = struct.unpack_from("<i", b, 1)[0]
assert 5 + rel == 14, (rel, 5 + rel)
expect_tail = bytes([
    0x48, 0xC7, 0xC0, 0x3C, 0x00, 0x00, 0x00,  # mov rax, 60
    0x0F, 0x05,                                 # syscall
    0x50,                                       # push rax
    0x48, 0xC7, 0xC7, 0x2A, 0x00, 0x00, 0x00,  # mov rdi, 42
    0x58,                                       # pop rax
    0xC3,                                       # ret
])
assert b[5:] == expect_tail, b[5:].hex()
print("callret bin OK", len(b), "bytes")
PY

objdump -d "$OUT/callret.o" | grep -q call
objdump -d "$OUT/callret.o" | grep -q ret
nm "$OUT/callret.o" | grep -E '[[:space:]]T[[:space:]]+_start$'

ld -o "$OUT/callret" "$OUT/callret.o"
set +e
"$OUT/callret"
st=$?
set -e
test "$st" -eq 42

echo "test_callret OK (call/ret/push/pop + exit 42)"
