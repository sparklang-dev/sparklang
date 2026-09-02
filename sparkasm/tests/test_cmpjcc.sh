#!/usr/bin/env bash
# cmp/test + jcc forward refs → linked exit 42
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/cmpjcc.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/cmpjcc.o" "$FIX"
"$ASM" --format=bin -o "$OUT/cmpjcc.bin" "$FIX"

python3 - "$OUT/cmpjcc.bin" <<'PY'
import pathlib, struct, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# mov rdi,5 (7) then cmp rdi,10
assert b[7:11] == bytes([0x48, 0x83, 0xFF, 0x0A]), b[7:11].hex()
assert b[11] == 0x0F and b[12] == 0x85, b[11:13].hex()
rel = struct.unpack_from("<i", b, 13)[0]
assert 17 + rel == 29, (rel, 17 + rel)  # jne → not_ten
# mov rdi,0 (7) then test rdi,rdi
assert b[29:36] == bytes([
    0x48, 0xC7, 0xC7, 0x00, 0x00, 0x00, 0x00,
]), b[29:36].hex()
assert b[36:39] == bytes([0x48, 0x85, 0xFF]), b[36:39].hex()
assert b[39] == 0x0F and b[40] == 0x84, b[39:41].hex()
rel2 = struct.unpack_from("<i", b, 41)[0]
assert 45 + rel2 == 57, (rel2, 45 + rel2)  # jz → exit42
print("cmpjcc bin OK", len(b), "bytes")
PY

objdump -d "$OUT/cmpjcc.o" | grep -q jne

ld -o "$OUT/cmpjcc" "$OUT/cmpjcc.o"
set +e
"$OUT/cmpjcc"
st=$?
set -e
test "$st" -eq 42

echo "test_cmpjcc OK (cmp/test+jcc forward refs + exit 42)"
