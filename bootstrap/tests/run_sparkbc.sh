#!/usr/bin/env bash
# Phase 0 SPARK_BC + honest Phase 3 hello compile (docs/SPARK_BC.md).
# Hello compile body matches GAS hello after the first banner.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# Makefile already built spark-bootstrap + spark (avoid remake races).
GOLDEN="selfhost/fixtures/hello.sparkbc"
EXPECT="bootstrap/tests/expected_hello_run_bc.txt"
fail=0

if [[ ! -f "$GOLDEN" ]]; then
  echo "FAIL sparkbc_hello: missing $GOLDEN"
  exit 1
fi

out="$(./spark-bootstrap --run-bc "$GOLDEN" 2>&1)" || {
  echo "FAIL sparkbc_hello: exit non-zero"
  echo "$out" | head -20
  exit 1
}
if ! printf '%s\n' "$out" | diff -u "$EXPECT" -; then
  echo "FAIL sparkbc_hello: stdout != expected (GAS body + bc banner)"
  fail=1
else
  echo "PASS sparkbc_hello"
fi

bad="$(mktemp)"
printf 'XXXX\x01' > "$bad"
set +e
bad_out="$(./spark-bootstrap --run-bc "$bad" 2>&1)"
bad_rc=$?
set -e
rm -f "$bad"
if [[ "$bad_rc" -eq 0 ]]; then
  echo "FAIL sparkbc_bad_magic: expected non-zero"
  fail=1
elif echo "$bad_out" | grep -q 'bad SPARK_BC magic'; then
  echo "PASS sparkbc_bad_magic"
else
  echo "FAIL sparkbc_bad_magic: missing magic error (rc=$bad_rc)"
  echo "$bad_out" | head -10
  fail=1
fi

unk="$(mktemp)"
cp "$GOLDEN" "$unk"
printf '\xff' | dd of="$unk" bs=1 seek=67 conv=notrunc status=none
set +e
unk_out="$(./spark-bootstrap --run-bc "$unk" 2>&1)"
unk_rc=$?
set -e
rm -f "$unk"
if [[ "$unk_rc" -eq 0 ]]; then
  echo "FAIL sparkbc_unknown_op: expected non-zero"
  fail=1
elif echo "$unk_out" | grep -q 'unknown SPARK_BC opcode'; then
  echo "PASS sparkbc_unknown_op"
else
  echo "FAIL sparkbc_unknown_op: missing opcode error (rc=$unk_rc)"
  echo "$unk_out" | head -10
  fail=1
fi

hello_dry="$(./spark-bootstrap --dry-run examples/hello.spark 2>&1)" || {
  echo "FAIL sparkbc_hello_dry_bc: exit non-zero"
  echo "$hello_dry" | head -10
  fail=1
}
if echo "$hello_dry" | grep -q 'dry-run via bytecode VM' &&
   echo "$hello_dry" | grep -q '\[print\] Gravity pulls masses together'; then
  echo "PASS sparkbc_hello_dry_bc"
else
  echo "FAIL sparkbc_hello_dry_bc: expected bytecode banner + gravity"
  echo "$hello_dry" | head -10
  fail=1
fi


set +e
uf="$(./spark-bootstrap --not-a-flag examples/hello.spark 2>&1)"
urc=$?
set -e
if [[ "$urc" -eq 0 ]]; then
  echo "FAIL sparkbc_unknown_flag: expected non-zero"
  fail=1
elif echo "$uf" | grep -q 'unknown flag'; then
  echo "PASS sparkbc_unknown_flag"
else
  echo "FAIL sparkbc_unknown_flag: $uf"
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

# Hello compile → --run-bc body == that file's GAS body after banner.
# Mini is a separate SoT file — compare to mini GAS, not hello gravity.
body_after_banner() {
  printf '%s\n' "$1" | tail -n +2
}

gas_hello="$(./spark --dry-run examples/hello.spark 2>&1)" || {
  echo "FAIL sparkbc_gas_hello: ./spark --dry-run exit non-zero"
  exit 1
}
hello_bc="/tmp/sparkbc_compile_hello.sparkbc"
./spark-bootstrap --compile examples/hello.spark -o "$hello_bc" || {
  echo "FAIL sparkbc_compile_hello: compile exit non-zero"
  exit 1
}
if ! cmp -s "$hello_bc" "$GOLDEN"; then
  echo "FAIL sparkbc_compile_hello: bytes != $GOLDEN"
  exit 1
fi
hello_run="$(./spark-bootstrap --run-bc "$hello_bc" 2>&1)" || {
  echo "FAIL sparkbc_compile_hello: run-bc exit non-zero"
  exit 1
}
if [[ "$(body_after_banner "$gas_hello")" != \
      "$(body_after_banner "$hello_run")" ]]; then
  echo "FAIL sparkbc_compile_hello: body != GAS after banner"
  exit 1
fi
if ! echo "$hello_run" | grep -q 'dry-run via bytecode VM'; then
  echo "FAIL sparkbc_compile_hello: missing bytecode banner"
  exit 1
fi
echo "PASS sparkbc_compile_hello"
rm -f "$hello_bc"

gas_mini="$(./spark --dry-run selfhost/fixtures/mini.spark 2>&1)" || {
  echo "FAIL sparkbc_gas_mini: ./spark --dry-run exit non-zero"
  exit 1
}
mini_bc="/tmp/sparkbc_compile_mini.sparkbc"
./spark-bootstrap --compile selfhost/fixtures/mini.spark -o "$mini_bc" || {
  echo "FAIL sparkbc_compile_mini: compile exit non-zero"
  exit 1
}
mini_run="$(./spark-bootstrap --run-bc "$mini_bc" 2>&1)" || {
  echo "FAIL sparkbc_compile_mini: run-bc exit non-zero"
  exit 1
}
if [[ "$(body_after_banner "$gas_mini")" != \
      "$(body_after_banner "$mini_run")" ]]; then
  echo "FAIL sparkbc_compile_mini: body != mini GAS after banner"
  printf '%s\n' "$(body_after_banner "$gas_mini")" | \
    diff -u - <(printf '%s\n' "$(body_after_banner "$mini_run")") || true
  exit 1
fi
echo "PASS sparkbc_compile_mini"
rm -f "$mini_bc"

gas_cls="$(./spark --dry-run selfhost/fixtures/classify_dry.spark \
  2>&1)" || {
  echo "FAIL sparkbc_gas_classify: ./spark --dry-run exit non-zero"
  exit 1
}
cls_bc="selfhost/fixtures/classify_dry.sparkbc"
cls_tmp="/tmp/sparkbc_compile_classify.sparkbc"
./spark-bootstrap --compile selfhost/fixtures/classify_dry.spark \
  -o "$cls_tmp" || {
  echo "FAIL sparkbc_compile_classify: compile exit non-zero"
  exit 1
}
if [[ -f "$cls_bc" ]] && ! cmp -s "$cls_tmp" "$cls_bc"; then
  echo "FAIL sparkbc_compile_classify: bytes != $cls_bc"
  exit 1
fi
cls_run="$(./spark-bootstrap --run-bc "$cls_tmp" 2>&1)" || {
  echo "FAIL sparkbc_compile_classify: run-bc exit non-zero"
  exit 1
}
if [[ "$(body_after_banner "$gas_cls")" != \
      "$(body_after_banner "$cls_run")" ]]; then
  echo "FAIL sparkbc_compile_classify: body != classify GAS"
  printf '%s\n' "$(body_after_banner "$gas_cls")" | \
    diff -u - <(printf '%s\n' "$(body_after_banner "$cls_run")") || true
  exit 1
fi
echo "PASS sparkbc_compile_classify"
rm -f "$cls_tmp"

gas_tool="$(./spark --dry-run examples/tool_agent.spark \
  2>&1)" || {
  echo "FAIL sparkbc_gas_tool: ./spark --dry-run exit non-zero"
  exit 1
}
tool_bc="selfhost/fixtures/tool_agent.sparkbc"
tool_tmp="/tmp/sparkbc_compile_tool.sparkbc"
./spark-bootstrap --compile examples/tool_agent.spark \
  -o "$tool_tmp" || {
  echo "FAIL sparkbc_compile_tool: compile exit non-zero"
  exit 1
}
if [[ -f "$tool_bc" ]] && ! cmp -s "$tool_tmp" "$tool_bc"; then
  echo "FAIL sparkbc_compile_tool: bytes != $tool_bc"
  exit 1
fi
tool_run="$(./spark-bootstrap --run-bc "$tool_tmp" 2>&1)" || {
  echo "FAIL sparkbc_compile_tool: run-bc exit non-zero"
  exit 1
}
if [[ "$(body_after_banner "$gas_tool")" != \
      "$(body_after_banner "$tool_run")" ]]; then
  echo "FAIL sparkbc_compile_tool: body != tool_agent GAS"
  printf '%s\n' "$(body_after_banner "$gas_tool")" | \
    diff -u - <(printf '%s\n' "$(body_after_banner "$tool_run")") || true
  exit 1
fi
echo "PASS sparkbc_compile_tool"
rm -f "$tool_tmp"

gas_ext="$(./spark-bootstrap --dry-run selfhost/fixtures/extract_dry.spark \
  2>&1)" || {
  echo "FAIL sparkbc_bootstrap_extract: --dry-run exit non-zero"
  exit 1
}
ext_bc="selfhost/fixtures/extract_dry.sparkbc"
ext_tmp="/tmp/sparkbc_compile_extract.sparkbc"
./spark-bootstrap --compile selfhost/fixtures/extract_dry.spark \
  -o "$ext_tmp" || {
  echo "FAIL sparkbc_compile_extract: compile exit non-zero"
  exit 1
}
if [[ -f "$ext_bc" ]] && ! cmp -s "$ext_tmp" "$ext_bc"; then
  echo "FAIL sparkbc_compile_extract: bytes != $ext_bc"
  exit 1
fi
ext_run="$(./spark-bootstrap --run-bc "$ext_tmp" 2>&1)" || {
  echo "FAIL sparkbc_compile_extract: run-bc exit non-zero"
  exit 1
}
if [[ "$(body_after_banner "$gas_ext")" != \
      "$(body_after_banner "$ext_run")" ]]; then
  echo "FAIL sparkbc_compile_extract: body != bootstrap dry-run"
  printf '%s\n' "$(body_after_banner "$gas_ext")" | \
    diff -u - <(printf '%s\n' "$(body_after_banner "$ext_run")") || true
  exit 1
fi
echo "PASS sparkbc_compile_extract"
rm -f "$ext_tmp"

gas_pipe="$(./spark-bootstrap --dry-run selfhost/fixtures/pipeline_dry.spark \
  2>&1)" || {
  echo "FAIL sparkbc_bootstrap_pipeline: --dry-run exit non-zero"
  exit 1
}
pipe_bc="selfhost/fixtures/pipeline_dry.sparkbc"
pipe_tmp="/tmp/sparkbc_compile_pipeline.sparkbc"
./spark-bootstrap --compile selfhost/fixtures/pipeline_dry.spark \
  -o "$pipe_tmp" || {
  echo "FAIL sparkbc_compile_pipeline: compile exit non-zero"
  exit 1
}
if [[ -f "$pipe_bc" ]] && ! cmp -s "$pipe_tmp" "$pipe_bc"; then
  echo "FAIL sparkbc_compile_pipeline: bytes != $pipe_bc"
  exit 1
fi
pipe_run="$(./spark-bootstrap --run-bc "$pipe_tmp" 2>&1)" || {
  echo "FAIL sparkbc_compile_pipeline: run-bc exit non-zero"
  exit 1
}
if [[ "$(body_after_banner "$gas_pipe")" != \
      "$(body_after_banner "$pipe_run")" ]]; then
  echo "FAIL sparkbc_compile_pipeline: body != bootstrap dry-run"
  printf '%s\n' "$(body_after_banner "$gas_pipe")" | \
    diff -u - <(printf '%s\n' "$(body_after_banner "$pipe_run")") || true
  exit 1
fi
if ! echo "$pipe_run" | grep -q '\[pipeline\] step'; then
  echo "FAIL sparkbc_compile_pipeline: missing [pipeline] step"
  exit 1
fi
echo "PASS sparkbc_compile_pipeline"
rm -f "$pipe_tmp"

gas_listen="$(./spark-bootstrap --dry-run selfhost/fixtures/listen_dry.spark \
  2>&1)" || {
  echo "FAIL sparkbc_bootstrap_listen: --dry-run exit non-zero"
  exit 1
}
listen_bc="selfhost/fixtures/listen_dry.sparkbc"
listen_tmp="/tmp/sparkbc_compile_listen.sparkbc"
./spark-bootstrap --compile selfhost/fixtures/listen_dry.spark \
  -o "$listen_tmp" || {
  echo "FAIL sparkbc_compile_listen: compile exit non-zero"
  exit 1
}
if [[ -f "$listen_bc" ]] && ! cmp -s "$listen_tmp" "$listen_bc"; then
  echo "FAIL sparkbc_compile_listen: bytes != $listen_bc"
  exit 1
fi
listen_run="$(./spark-bootstrap --run-bc "$listen_tmp" 2>&1)" || {
  echo "FAIL sparkbc_compile_listen: run-bc exit non-zero"
  exit 1
}
if [[ "$(body_after_banner "$gas_listen")" != \
      "$(body_after_banner "$listen_run")" ]]; then
  echo "FAIL sparkbc_compile_listen: body != bootstrap dry-run"
  printf '%s\n' "$(body_after_banner "$gas_listen")" | \
    diff -u - <(printf '%s\n' "$(body_after_banner "$listen_run")") || true
  exit 1
fi
if ! echo "$listen_run" | grep -q '\[listen\] My account is locked'; then
  echo "FAIL sparkbc_compile_listen: missing dry transcript line"
  exit 1
fi
echo "PASS sparkbc_compile_listen"
rm -f "$listen_tmp"

gas_speak="$(./spark-bootstrap --dry-run selfhost/fixtures/speak_dry.spark \
  2>&1)" || {
  echo "FAIL sparkbc_bootstrap_speak: --dry-run exit non-zero"
  exit 1
}
speak_bc="selfhost/fixtures/speak_dry.sparkbc"
speak_tmp="/tmp/sparkbc_compile_speak.sparkbc"
./spark-bootstrap --compile selfhost/fixtures/speak_dry.spark \
  -o "$speak_tmp" || {
  echo "FAIL sparkbc_compile_speak: compile exit non-zero"
  exit 1
}
if [[ -f "$speak_bc" ]] && ! cmp -s "$speak_tmp" "$speak_bc"; then
  echo "FAIL sparkbc_compile_speak: bytes != $speak_bc"
  exit 1
fi
speak_run="$(./spark-bootstrap --run-bc "$speak_tmp" 2>&1)" || {
  echo "FAIL sparkbc_compile_speak: run-bc exit non-zero"
  exit 1
}
if [[ "$(body_after_banner "$gas_speak")" != \
      "$(body_after_banner "$speak_run")" ]]; then
  echo "FAIL sparkbc_compile_speak: body != bootstrap dry-run"
  printf '%s\n' "$(body_after_banner "$gas_speak")" | \
    diff -u - <(printf '%s\n' "$(body_after_banner "$speak_run")") || true
  exit 1
fi
if ! echo "$speak_run" | grep -q '\[speak\] wrote out/bootstrap_speak.wav'; then
  echo "FAIL sparkbc_compile_speak: missing dry speak line"
  exit 1
fi
echo "PASS sparkbc_compile_speak"
rm -f "$speak_tmp"

# Phase 4 engine + ide: compile → bc_vm roundtrip.
for src in bootstrap/fixtures/engine_fetch.spark bootstrap/fixtures/engine_parse.spark bootstrap/fixtures/engine_css.spark bootstrap/fixtures/engine_layout.spark bootstrap/fixtures/engine_paint.spark bootstrap/fixtures/engine_show.spark bootstrap/fixtures/engine_render.spark selfhost/fixtures/ide_dry.spark; do
  base="$(basename "$src" .spark)"
  bc="/tmp/sparkbc_compile_${base}.sparkbc"
  ./spark-bootstrap --compile "$src" -o "$bc" || { echo "FAIL sparkbc_compile_${base}: compile"; fail=1; continue; }
  out="$(./spark-bootstrap --run-bc "$bc" 2>&1)" || { echo "FAIL sparkbc_compile_${base}: run-bc"; fail=1; rm -f "$bc"; continue; }
  if echo "$out" | grep -q '\[spark\] ok'; then echo "PASS sparkbc_compile_${base}"; else echo "FAIL sparkbc_compile_${base}: no ok"; fail=1; fi
  rm -f "$bc"
done
if [[ "$fail" -ne 0 ]]; then exit 1; fi

# Phase 4 voice/browser/mitm: compile → run-bc GAS parity.
parity_case() {
  local name="$1"
  local src="$2"
  local golden="${3:-}"
  local gas run
  gas="$(./spark --dry-run "$src" 2>&1)" || {
    echo "FAIL sparkbc_compile_${name}: GAS exit non-zero"
    fail=1
    return
  }
  local bc="/tmp/sparkbc_compile_${name}.sparkbc"
  ./spark-bootstrap --compile "$src" -o "$bc" || {
    echo "FAIL sparkbc_compile_${name}: compile exit non-zero"
    fail=1
    return
  }
  if [[ -n "$golden" && -f "$golden" ]] && ! cmp -s "$bc" "$golden"; then
    echo "FAIL sparkbc_compile_${name}: bytes != $golden"
    fail=1
    rm -f "$bc"
    return
  fi
  run="$(./spark-bootstrap --run-bc "$bc" 2>&1)" || {
    echo "FAIL sparkbc_compile_${name}: run-bc exit non-zero"
    fail=1
    rm -f "$bc"
    return
  }
  if [[ "$(body_after_banner "$gas")" != "$(body_after_banner "$run")" ]]; then
    echo "FAIL sparkbc_compile_${name}: body != GAS after banner"
    printf '%s\n' "$(body_after_banner "$gas")" | \
      diff -u - <(printf '%s\n' "$(body_after_banner "$run")") || true
    fail=1
  else
    echo "PASS sparkbc_compile_${name}"
  fi
  rm -f "$bc"
}

parity_case review_voice selfhost/fixtures/review_voice.spark \
  selfhost/fixtures/review_voice.sparkbc
parity_case browser_dry selfhost/fixtures/browser_dry.spark \
  selfhost/fixtures/browser_dry.sparkbc
parity_case browser_run_goto bootstrap/fixtures/browser_run_goto.spark \
  selfhost/fixtures/browser_run_goto.sparkbc
parity_case mitm_enable bootstrap/fixtures/mitm_enable.spark \
  selfhost/fixtures/mitm_enable.sparkbc

rev_dry="$(./spark-bootstrap --dry-run selfhost/fixtures/review_voice.spark 2>&1)" || {
  echo "FAIL sparkbc_review_dry_bc: exit non-zero"
  fail=1
}
if echo "$rev_dry" | grep -q 'dry-run via bytecode VM' &&
   echo "$rev_dry" | grep -q '\[voice\] session'; then
  echo "PASS sparkbc_review_dry_bc"
else
  echo "FAIL sparkbc_review_dry_bc"
  echo "$rev_dry" | head -15
  fail=1
fi


# use auto keeps prior model (no Bifrost-style alias pick).
for auto_tag in use_auto_fast use_auto_code; do
  case "$auto_tag" in
    use_auto_fast) auto_ask='Gravity pulls' ;;
    use_auto_code) auto_ask='Fix: update' ;;
  esac
  auto_src="selfhost/fixtures/${auto_tag}.spark"
  auto_bc="selfhost/fixtures/${auto_tag}.sparkbc"
  ./spark-bootstrap --compile "$auto_src" -o "$auto_bc" || {
    echo "FAIL sparkbc_compile_${auto_tag}: compile"
    fail=1
    continue
  }
  auto_run="$(./spark-bootstrap --run-bc "$auto_bc" 2>&1)" || {
    echo "FAIL sparkbc_compile_${auto_tag}: run-bc"
    fail=1
    continue
  }
  auto_dry="$(./spark-bootstrap --dry-run "$auto_src" 2>&1)" || {
    echo "FAIL sparkbc_dry_${auto_tag}: dry-run"
    fail=1
    continue
  }
  if echo "$auto_run" | grep -q 'dry-run via bytecode VM' &&
     echo "$auto_run" | grep -q 'prior .* (no alias pick)' &&
     echo "$auto_run" | grep -qvE 'auto→(fast|code)' &&
     echo "$auto_run" | grep -qE "$auto_ask" &&
     echo "$auto_dry" | grep -q 'dry-run via bytecode VM' &&
     echo "$auto_dry" | grep -q 'prior .* (no alias pick)'; then
    echo "PASS sparkbc_${auto_tag}"
  else
    echo "FAIL sparkbc_${auto_tag}"
    echo "$auto_run" | head -12
    fail=1
  fi
done

# TRAIN / TRAIN_STATUS must *run* from the published SPARK_BC, not
# only encode. Dry fixture + ARTIFACT marker. Not SGD. Not trained.
pub_bc="docs/examples/spark-builder.sparkbc"
marker="out/train/job-dry-001/ARTIFACT"
builder_tmp="$(mktemp)"
./spark-bootstrap --compile examples/spark_builder.spark \
  -o "$builder_tmp" || {
  echo "FAIL sparkbc_builder_train: compile"
  fail=1
}
if [[ "$fail" -eq 0 && ! -f "$pub_bc" ]]; then
  echo "FAIL sparkbc_builder_train: missing $pub_bc"
  fail=1
fi
if [[ "$fail" -eq 0 ]] && ! cmp -s "$builder_tmp" "$pub_bc"; then
  echo "FAIL sparkbc_builder_train: compile != $pub_bc"
  fail=1
fi
rm -f "$marker"
if [[ "$fail" -eq 0 ]]; then
  builder_run="$(./spark-bootstrap --run-bc "$pub_bc" 2>&1)" || {
    echo "FAIL sparkbc_builder_train: run-bc"
    echo "$builder_run" | head -12
    fail=1
  }
fi
if [[ "$fail" -eq 0 ]]; then
  if PYTHONPATH=python python3 -c "
from sparklang.model_lab.bc_dump import decode_ops, load_sparkbc
bc = load_sparkbc('$pub_bc')
ops = [o['name'] for o in decode_ops(bc)]
assert 'TRAIN' in ops, ops
assert 'TRAIN_STATUS' in ops, ops
assert 0x26 in bc['code'], bc['code'][:16]
assert 0x27 in bc['code'], 'no TRAIN_STATUS'
print('decoded', ' '.join(ops), 'sha256', bc['sha256'][:12])
"; then
    if echo "$builder_run" | grep -q '"op":"train"' &&
       echo "$builder_run" | grep -q '"op":"status"' &&
       echo "$builder_run" | grep -q 'job-dry-001' &&
       echo "$builder_run" | grep -q 'dry-run' &&
       test -f "$marker" &&
       grep -q 'not_sgd=true' "$marker" &&
       grep -q 'trained=false' "$marker"; then
      echo "PASS sparkbc_builder_train"
    else
      echo "FAIL sparkbc_builder_train: run/status/marker miss"
      echo "$builder_run" | head -16
      fail=1
    fi
  else
    echo "FAIL sparkbc_builder_train: TRAIN opcode missing"
    fail=1
  fi
fi
rm -f "$builder_tmp"

# STEP 0x28: TRAIN → STEP → TRAIN_STATUS in one stream.
# STEP runs CPU SGD → out/train/<job>/weights.safetensors
# (trained=true, not_sgd=false). Tiny; not beat Claude.
step_src="examples/spark_train_step.spark"
step_pub="docs/examples/spark-train-step.sparkbc"
step_tmp="$(mktemp)"
marker="out/train/job-dry-001/ARTIFACT"
weights="out/train/job-dry-001/weights.safetensors"
./spark-bootstrap --compile "$step_src" -o "$step_tmp" || {
  echo "FAIL sparkbc_train_step: compile"
  fail=1
}
if [[ "$fail" -eq 0 && ! -f "$step_pub" ]]; then
  echo "FAIL sparkbc_train_step: missing $step_pub"
  fail=1
fi
if [[ "$fail" -eq 0 ]] && ! cmp -s "$step_tmp" "$step_pub"; then
  echo "FAIL sparkbc_train_step: compile != $step_pub"
  fail=1
fi
rm -f "$marker" "$weights"
if [[ "$fail" -eq 0 ]]; then
  step_run="$(./spark-bootstrap --run-bc "$step_pub" 2>&1)" || {
    echo "FAIL sparkbc_train_step: run-bc"
    echo "$step_run" | head -12
    fail=1
  }
fi
if [[ "$fail" -eq 0 ]]; then
  if PYTHONPATH=python python3 -c "
from sparklang.model_lab.bc_dump import load_sparkbc
from sparklang.model_lab.weights import read_safetensors_meta
bc = load_sparkbc('$step_pub')
code = bc['code']
assert 0x26 in code and 0x28 in code and 0x27 in code, list(code)
i26, i28, i27 = code.index(0x26), code.index(0x28), code.index(0x27)
assert i26 < i28 < i27, (i26, i28, i27)
meta = read_safetensors_meta('$weights')
assert int(meta.get('step_n', '0')) >= 1, meta
assert meta.get('trained') == 'true', meta
assert meta.get('not_sgd') == 'false', meta
assert meta.get('sgd') == 'true', meta
lb = float(meta['loss_before'])
la = float(meta['loss_after'])
assert la < lb, (lb, la)
print('sha256', bc['sha256'])
print('weights_step_n', meta['step_n'])
print('loss', lb, '->', la)
print('first32', ' '.join('%02x' % b for b in bc['raw'][:32]))
"; then
    if echo "$step_run" | grep -q '"op":"train"' &&
       echo "$step_run" | grep -q '"op":"step"' &&
       echo "$step_run" | grep -q '"op":"status"' &&
       echo "$step_run" | grep -q 'job-dry-001' &&
       echo "$step_run" | grep -q 'weights.safetensors' &&
       echo "$step_run" | grep -q 'cpu-sgd' &&
       test -f "$marker" &&
       test -f "$weights" &&
       test -f "out/train/job-dry-001/checkpoint.json" &&
       grep -q 'step_n=1' "$marker" &&
       grep -q 'trained=true' "$marker" &&
       grep -q 'not_sgd=false' "$marker" &&
       grep -q 'checkpoint=' "$marker" &&
       grep -q 'weights=' "$marker"; then
      echo "PASS sparkbc_train_step"
    else
      echo "FAIL sparkbc_train_step: run/marker/weights miss"
      echo "$step_run" | head -20
      fail=1
    fi
  else
    echo "FAIL sparkbc_train_step: opcode/weights meta"
    fail=1
  fi
fi
rm -f "$step_tmp"

# GAS ./spark --run-bc / --compile thin-wrap spark-bootstrap.
# bc_vm + C lowering remain SoT; wrappers are argv convenience.
set +e
gas_bc_out="$(./spark --run-bc "$pub_bc" 2>&1)"
gas_bc_rc=$?
set -e
if [[ "$gas_bc_rc" -ne 0 ]]; then
  echo "FAIL sparkbc_gas_run_bc: ./spark --run-bc exit $gas_bc_rc"
  echo "$gas_bc_out" | head -8
  fail=1
elif ! echo "$gas_bc_out" | grep -q '"op":"train"'; then
  echo "FAIL sparkbc_gas_run_bc: missing train JSON"
  echo "$gas_bc_out" | head -8
  fail=1
elif echo "$gas_bc_out" | grep -Fq 'need --dry-run|--live'; then
  echo "FAIL sparkbc_gas_run_bc: still BLOCKED (old argv path)"
  fail=1
else
  echo "PASS sparkbc_gas_run_bc (./spark --run-bc → bootstrap bc_vm)"
fi

gas_emit="/tmp/sparkbc-gas-emit-$$.sparkbc"
rm -f "$gas_emit"
set +e
gas_comp_out="$(./spark --compile examples/spark_builder.spark \
  -o "$gas_emit" 2>&1)"
gas_comp_rc=$?
set -e
if [[ "$gas_comp_rc" -ne 0 ]]; then
  echo "FAIL sparkbc_gas_compile: exit $gas_comp_rc"
  echo "$gas_comp_out" | head -8
  fail=1
elif [[ ! -f "$gas_emit" ]]; then
  echo "FAIL sparkbc_gas_compile: missing $gas_emit"
  fail=1
elif ! cmp -s "$gas_emit" "$pub_bc"; then
  echo "FAIL sparkbc_gas_compile: bytes != published builder"
  fail=1
else
  echo "PASS sparkbc_gas_compile (./spark --compile → bootstrap)"
fi
rm -f "$gas_emit"

if [[ "$fail" -ne 0 ]]; then exit 1; fi

echo "OK sparkbc"
