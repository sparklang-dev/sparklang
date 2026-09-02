#!/usr/bin/env bash
# Safe CUDA/host hygiene for this host Spark policy.
# Never: host reboot, rmmod under voice/vLLM, load Spark on voice GPU.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPORT_DIR="${REPORT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)/reports}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${REPORT_DIR}/spark-cuda-hygiene-${STAMP}.log"

{
  echo "=== spark CUDA safe hygiene $STAMP ==="
  echo "cwd=$ROOT"
  echo "--- persistence (safe; already usually on) ---"
  nvidia-smi -pm 1 || true
  echo "--- current link / memory ---"
  nvidia-smi --query-gpu=index,name,persistence_mode,memory.used,memory.total,pcie.link.gen.current,pcie.link.width.current,pcie.link.width.max --format=csv
  echo "--- policy ---"
  if [[ -f "$ROOT/spark-cuda.toml" ]]; then
    cat "$ROOT/spark-cuda.toml"
  else
    echo "missing spark-cuda.toml"
  fi
  echo "--- notes ---"
  echo "prefer-GPU LnkSta may be downgraded vs Max: hardware/BIOS;"
  echo "  fix needs owner console (reseating/BIOS) + reboot — agent-blocked."
  echo "reserved index = voice-only; Spark CUDA demos must not use it."
  echo "HugePages_Total=0; THP=madvise — do not allocate hugepages without owner."
} | tee "$OUT"

echo "wrote $OUT"
