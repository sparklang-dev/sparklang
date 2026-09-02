#!/usr/bin/env bash
# push imm → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/pushimm.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/pushimm.o" "$FIX"
"$ASM" --format=bin -o "$OUT/pushimm.bin" "$FIX"

python3 - "$OUT/pushimm.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# push 42 — GAS: pushq $42 → 6a 2a
assert b[0:2] == bytes([0x6A, 0x2A]), b[0:2].hex()
# pop rdi
assert b[2:3] == bytes([0x5F]), b[2:3].hex()
# mov rax,60 + syscall
assert b[3:10] == bytes([
    0x48, 0xC7, 0xC0, 0x3C, 0x00, 0x00, 0x00,
]), b[3:10].hex()
assert b[10:12] == bytes([0x0F, 0x05]), b[10:12].hex()
print("pushimm bin OK", len(b), "bytes")
PY

objdump -d "$OUT/pushimm.o" | grep -q 'push.*\$0x2a\|push.*\$42'

ld -o "$OUT/pushimm" "$OUT/pushimm.o"
set +e
"$OUT/pushimm"
st=$?
set -e
test "$st" -eq 42

echo "test_pushimm OK (push imm + exit 42)"
