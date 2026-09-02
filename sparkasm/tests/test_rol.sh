#!/usr/bin/env bash
# rol → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/rol.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/rol.o" "$FIX"
"$ASM" --format=bin -o "$OUT/rol.bin" "$FIX"

python3 - "$OUT/rol.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,21
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC7, 0x15, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# rol rdi,1 — GAS: rol $1,%rdi → 48 d1 c7
assert b[7:10] == bytes([0x48, 0xD1, 0xC7]), b[7:10].hex()
print("rol bin OK", len(b), "bytes")
PY

objdump -d "$OUT/rol.o" | grep -q rol

ld -o "$OUT/rol" "$OUT/rol.o"
set +e
"$OUT/rol"
st=$?
set -e
test "$st" -eq 42

echo "test_rol OK (rol + exit 42)"
