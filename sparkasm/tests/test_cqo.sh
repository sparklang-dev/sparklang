#!/usr/bin/env bash
# cqo → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/cqo.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/cqo.o" "$FIX"
"$ASM" --format=bin -o "$OUT/cqo.bin" "$FIX"

python3 - "$OUT/cqo.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rax,42
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC0, 0x2A, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# cqo — GAS: cqo → 48 99
assert b[7:9] == bytes([0x48, 0x99]), b[7:9].hex()
# mov rdi,rax — GAS: mov %rax,%rdi → 48 89 c7
assert b[9:12] == bytes([0x48, 0x89, 0xC7]), b[9:12].hex()
# mov rax,60 + syscall
assert b[12:19] == bytes([
    0x48, 0xC7, 0xC0, 0x3C, 0x00, 0x00, 0x00,
]), b[12:19].hex()
assert b[19:21] == bytes([0x0F, 0x05]), b[19:21].hex()
print("cqo bin OK", len(b), "bytes")
PY

objdump -d "$OUT/cqo.o" | grep -Eq 'cqo|cqto'

ld -o "$OUT/cqo" "$OUT/cqo.o"
set +e
"$OUT/cqo"
st=$?
set -e
test "$st" -eq 42

echo "test_cqo OK (cqo + exit 42)"
