#!/usr/bin/env bash
# ror → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/ror.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/ror.o" "$FIX"
"$ASM" --format=bin -o "$OUT/ror.bin" "$FIX"

python3 - "$OUT/ror.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,84
assert b[0:7] == bytes([
    0x48, 0xC7, 0xC7, 0x54, 0x00, 0x00, 0x00,
]), b[0:7].hex()
# ror rdi,1 — GAS: ror $1,%rdi → 48 d1 cf
assert b[7:10] == bytes([0x48, 0xD1, 0xCF]), b[7:10].hex()
print("ror bin OK", len(b), "bytes")
PY

objdump -d "$OUT/ror.o" | grep -q ror

ld -o "$OUT/ror" "$OUT/ror.o"
set +e
"$OUT/ror"
st=$?
set -e
test "$st" -eq 42

echo "test_ror OK (ror + exit 42)"
