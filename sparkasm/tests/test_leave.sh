#!/usr/bin/env bash
# leave → linked exit 42 (GAS-proven bytes)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASM="$ROOT/sparkasm"
FIX="$ROOT/fixtures/leave.sasm"
OUT="$ROOT/out"
mkdir -p "$OUT"

"$ASM" -o "$OUT/leave.o" "$FIX"
"$ASM" --format=bin -o "$OUT/leave.bin" "$FIX"

python3 - "$OUT/leave.bin" <<'PY'
import pathlib, sys

b = pathlib.Path(sys.argv[1]).read_bytes()
# push rbp
assert b[0:1] == bytes([0x55]), b[0:1].hex()
# mov rbp,rsp — GAS: mov %rsp,%rbp → 48 89 e5
assert b[1:4] == bytes([0x48, 0x89, 0xE5]), b[1:4].hex()
# mov rdi,42
assert b[4:11] == bytes([
    0x48, 0xC7, 0xC7, 0x2A, 0x00, 0x00, 0x00,
]), b[4:11].hex()
# leave — GAS: leave → c9
assert b[11:12] == bytes([0xC9]), b[11:12].hex()
print("leave bin OK", len(b), "bytes")
PY

objdump -d "$OUT/leave.o" | grep -q leave

ld -o "$OUT/leave" "$OUT/leave.o"
set +e
"$OUT/leave"
st=$?
set -e
test "$st" -eq 42

echo "test_leave OK (leave + exit 42)"
