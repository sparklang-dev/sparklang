#!/usr/bin/env bash
# sar → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/sar.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/sar.o" "$FIX"
"$ASM" --format=bin -o "$OUT/sar.bin" "$FIX"

python3 - "$OUT/sar.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,-84
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC7, 0xAC, 0xFF, 0xFF, 0xFF,
]), b[0:7].hex()
# sar rdi,1 — GAS: sar $1,%rdi → 48 d1 ff
assert b[7:10] == bytes([0x48, 0xD1, 0xFF]), b[7:10].hex()
# neg rdi
assert b[10:13] == bytes([0x48, 0xF7, 0xDF]), b[10:13].hex()
print("sar bin OK", len(b), "bytes")
PY

objdump -d "$OUT/sar.o" | grep -q sar

ld -o "$OUT/sar" "$OUT/sar.o"
set +e
"$OUT/sar"
st=$?
set -e
test "$st" -eq 42

echo "test_sar OK (sar + exit 42)"
