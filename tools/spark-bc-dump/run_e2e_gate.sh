#!/usr/bin/env bash
# SparkBC e2e gate: compile spark_train_step → dump TRAIN/STEP →
# bootstrap --run-bc → GAS ./spark --run-bc → assert ARTIFACT.
# STEP runs multi-outer CPU SGD (trained=true). Not beat Claude.
#
# STEP weights + loss drop are covered by make test-sparkbc.
# This gate asserts ARTIFACT + opcode stream.
#
# Usage (from repo root):
#   make sparkbc-e2e
#   ./tools/spark-bc-dump/run_e2e_gate.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

STEP_SRC="examples/spark_train_step.spark"
STEP_PUB="docs/examples/spark-train-step.sparkbc"
STEP_SHA256="d08925b52bf8c840de626c9cfec619d4dbae5a674b94bb8c7c5837eb1ac64551"
MARKER="out/train/job-dry-001/ARTIFACT"
BOOT="./spark-bootstrap"

if [[ ! -x "$BOOT" ]]; then
  echo "FAIL sparkbc-e2e: missing $BOOT (make spark-bootstrap)"
  exit 1
fi
if [[ ! -f "$STEP_SRC" ]]; then
  echo "FAIL sparkbc-e2e: missing $STEP_SRC"
  exit 1
fi

echo "=== sparkbc-e2e: compile ==="
step_tmp="$(mktemp)"
trap 'rm -f "$step_tmp"' EXIT
"$BOOT" --compile "$STEP_SRC" -o "$step_tmp"
if [[ ! -f "$STEP_PUB" ]]; then
  echo "FAIL sparkbc-e2e: missing published $STEP_PUB"
  exit 1
fi
if ! cmp -s "$step_tmp" "$STEP_PUB"; then
  echo "FAIL sparkbc-e2e: compile != published $STEP_PUB"
  exit 1
fi
got_sha="$(sha256sum "$STEP_PUB" | awk '{print $1}')"
if [[ "$got_sha" != "$STEP_SHA256" ]]; then
  echo "FAIL sparkbc-e2e: sha256 mismatch"
  echo "  want $STEP_SHA256"
  echo "  got  $got_sha"
  exit 1
fi
echo "PASS compile ($STEP_SRC → $STEP_PUB)"

echo "=== sparkbc-e2e: dump decode TRAIN/STEP ==="
PYTHONPATH=python python3 - <<'PY'
from pathlib import Path

from sparklang.model_lab.bc_dump import (
    decode_ops,
    format_dump,
    load_sparkbc,
)

root = Path(".")
pub = root / "docs/examples/spark-train-step.sparkbc"
dump_path = root / "docs/examples/spark-train-step-bc.txt"
src = "examples/spark_train_step.spark"
cmd = (
    "./spark-bootstrap --compile examples/spark_train_step.spark "
    "-o docs/examples/spark-train-step.sparkbc"
)
want = (
    "d08925b52bf8c840de626c9cfec619d4dbae5a674b94bb8c7c5837eb1ac64551"
)
bc = load_sparkbc(pub)
assert bc["sha256"] == want, bc["sha256"]
ops = decode_ops(bc)
names = [o["name"] for o in ops]
assert "TRAIN" in names and "STEP" in names, names
assert "TRAIN_STATUS" in names, names
i_train = names.index("TRAIN")
i_step = names.index("STEP")
i_status = names.index("TRAIN_STATUS")
assert i_train < i_step < i_status, names
step = ops[i_step]
assert step["op"] == 0x28
assert step["hex"].startswith("28 ")
dump = format_dump(
    bc,
    source=src,
    command=cmd,
    label="Train-step SPARK_BC (TRAIN → STEP → TRAIN_STATUS)",
)
assert "TRAIN (0x26)" in dump
assert "STEP (0x28)" in dump
assert "TRAIN_STATUS (0x27)" in dump
assert "28 07 00 06 00" in dump
dump_path.write_text(dump, encoding="utf-8")
print("decoded", " ".join(names))
print("sha256", bc["sha256"][:12])
print("dump", dump_path)
PY
echo "PASS dump decode"

echo "=== sparkbc-e2e: --run-bc (CPU SGD STEP) ==="
rm -f "$MARKER"
step_run="$("$BOOT" --run-bc "$STEP_PUB" 2>&1)" || {
  echo "FAIL sparkbc-e2e: --run-bc exit non-zero"
  echo "$step_run" | head -20
  exit 1
}
echo "$step_run" | grep -q '"op":"train"' || {
  echo "FAIL sparkbc-e2e: missing train JSON"
  echo "$step_run" | head -16
  exit 1
}
echo "$step_run" | grep -q '"op":"step"' || {
  echo "FAIL sparkbc-e2e: missing step JSON"
  echo "$step_run" | head -16
  exit 1
}
echo "$step_run" | grep -q '"op":"status"' || {
  echo "FAIL sparkbc-e2e: missing status JSON"
  echo "$step_run" | head -16
  exit 1
}
echo "$step_run" | grep -q 'job-dry-001' || {
  echo "FAIL sparkbc-e2e: missing job-dry-001"
  exit 1
}
echo "$step_run" | grep -q 'cpu-sgd' || {
  echo "FAIL sparkbc-e2e: missing cpu-sgd mode"
  exit 1
}
echo "PASS --run-bc cpu-sgd"

echo "=== sparkbc-e2e: GAS ./spark --run-bc ==="
GAS="${ROOT}/spark"
if [[ ! -x "$GAS" ]]; then
  echo "FAIL sparkbc-e2e: missing $GAS (make spark)"
  exit 1
fi
rm -f "$MARKER"
gas_run="$("$GAS" --run-bc "$STEP_PUB" 2>&1)" || {
  echo "FAIL sparkbc-e2e: GAS --run-bc exit non-zero"
  echo "$gas_run" | head -20
  exit 1
}
echo "$gas_run" | grep -q '"op":"train"' || {
  echo "FAIL sparkbc-e2e: GAS missing train JSON"
  echo "$gas_run" | head -8
  exit 1
}
echo "$gas_run" | grep -q '"op":"step"' || {
  echo "FAIL sparkbc-e2e: GAS missing step JSON"
  exit 1
}
echo "$gas_run" | grep -q '"op":"status"' || {
  echo "FAIL sparkbc-e2e: GAS missing status JSON"
  exit 1
}
if [[ ! -f "$MARKER" ]]; then
  echo "FAIL sparkbc-e2e: GAS --run-bc missing $MARKER"
  exit 1
fi
echo "PASS GAS --run-bc"

echo "=== sparkbc-e2e: ARTIFACT ==="
if [[ ! -f "$MARKER" ]]; then
  echo "FAIL sparkbc-e2e: missing $MARKER"
  exit 1
fi
grep -q 'not_sgd=false' "$MARKER" || {
  echo "FAIL sparkbc-e2e: ARTIFACT missing not_sgd=false"
  cat "$MARKER"
  exit 1
}
grep -q 'trained=true' "$MARKER" || {
  echo "FAIL sparkbc-e2e: ARTIFACT missing trained=true"
  cat "$MARKER"
  exit 1
}
grep -q 'step_n=1' "$MARKER" || {
  echo "FAIL sparkbc-e2e: ARTIFACT missing step_n=1"
  cat "$MARKER"
  exit 1
}
grep -q 'checkpoint=' "$MARKER" || {
  echo "FAIL sparkbc-e2e: ARTIFACT missing checkpoint="
  cat "$MARKER"
  exit 1
}
CKPT="out/train/job-dry-001/checkpoint.json"
if [[ ! -f "$CKPT" ]]; then
  echo "FAIL sparkbc-e2e: missing $CKPT"
  exit 1
fi
PYTHONPATH=python python3 -c "
import json
c=json.load(open('$CKPT'))
assert c['loss_after'] < c['loss_before'], c
assert c['beats_claude'] is False, c
assert c['device'] == 'cpu', c
assert len(c.get('loss_curve') or []) >= 2, c
print('checkpoint loss', c['loss_before'], '->', c['loss_after'])
"
echo "PASS ARTIFACT ($MARKER) + checkpoint"

# Optional: SPARKBC_E2E_REQUIRE_STEP_WEIGHTS=1 also asserts weights here.
WEIGHTS="out/train/job-dry-001/weights.safetensors"
if [[ -n "${SPARKBC_E2E_REQUIRE_STEP_WEIGHTS:-}" ]]; then
  if [[ ! -f "$WEIGHTS" ]]; then
    echo "FAIL sparkbc-e2e: missing $WEIGHTS"
    exit 1
  fi
  echo "PASS STEP weights ($WEIGHTS)"
fi

echo "OK sparkbc-e2e (ARTIFACT + TRAIN/STEP; CPU SGD via test-sparkbc)"
