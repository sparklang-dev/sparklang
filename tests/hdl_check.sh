#!/usr/bin/env bash
# HDL lane for make test — real compile or honest SKIP (never fake pass).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -d hdl ]]; then
  echo "SKIP hdl (hdl/ directory absent)"
  exit 0
fi

vfiles=(hdl/*.v)
if [[ ! -e "${vfiles[0]}" ]]; then
  echo "SKIP hdl (no hdl/*.v sources)"
  exit 0
fi

if ! command -v iverilog >/dev/null 2>&1; then
  echo "SKIP hdl-compile (iverilog not on PATH — install Icarus Verilog for real compile; not a fake pass)"
  exit 0
fi

out="/tmp/spark-hdl-classify-$$.vvp"
trap 'rm -f "$out"' EXIT

# Real compile (SystemVerilog $clog2 needs -g2012)
if iverilog -g2012 -o "$out" hdl/classify_score.v; then
  echo "PASS hdl-compile (iverilog classify_score.v → $(basename "$out"))"
  exit 0
fi

echo "FAIL hdl-compile (iverilog rejected hdl/classify_score.v)"
exit 1
