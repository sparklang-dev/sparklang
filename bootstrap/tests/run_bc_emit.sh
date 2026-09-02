#!/usr/bin/env bash
# Phase 5: .sparkbc → sasm → ELF (sparkasm, not GAS).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

make -s sparkasm spark-bc-emit spark-bc-pack-hello spark-bootstrap

emit_elf() {
  local bc="$1"
  local tag="$2"
  local sasm="/tmp/spark-bc-emit-${tag}.sasm"
  local obj="/tmp/spark-bc-emit-${tag}.o"
  local bin="/tmp/spark-bc-emit-${tag}"

  ./spark-bc-emit "$bc" > "$sasm"
  ./sparkasm/sparkasm -o "$obj" "$sasm"
  ld -o "$bin" "$obj"
  "$bin"
  local rc=$?
  rm -f "$sasm" "$obj" "$bin"
  return "$rc"
}

body_after_bc_banner() {
  awk 'found{print} /\[spark\] dry-run via bytecode VM/{found=1}' "$1" \
    | sed '$d'
}

# layout.table cell_text is deterministic after PIE band fix; no mask.
parity_normalize() {
  cat
}

emit_elf_parity() {
  local bc="$1"
  local tag="$2"
  local sasm="/tmp/spark-bc-emit-${tag}.sasm"
  local obj="/tmp/spark-bc-emit-${tag}.o"
  local bin="/tmp/spark-bc-emit-${tag}"
  local vm_out="/tmp/spark-bc-emit-${tag}.vm"
  local em_out="/tmp/spark-bc-emit-${tag}.em"

  ./spark-bootstrap --run-bc "$bc" > "$vm_out" 2>&1
  ./spark-bc-emit "$bc" > "$sasm"
  ./sparkasm/sparkasm -o "$obj" "$sasm"
  ld -o "$bin" "$obj"
  "$bin" > "$em_out" 2>&1
  local rc=$?
  if [[ "$rc" -ne 0 ]]; then
    rm -f "$sasm" "$obj" "$bin" "$vm_out" "$em_out"
    return "$rc"
  fi
  body_after_bc_banner "$vm_out" | parity_normalize > "${vm_out}.body"
  if [[ -s "${vm_out}.body" ]]; then
    parity_normalize < "$em_out" > "${em_out}.body"
    if ! diff -u "${vm_out}.body" "${em_out}.body"; then
      rm -f "$sasm" "$obj" "$bin" "$vm_out" "$em_out" \
        "${vm_out}.body" "${em_out}.body"
      return 1
    fi
  fi
  rm -f "$sasm" "$obj" "$bin" "$vm_out" "$em_out" \
    "${vm_out}.body" "${em_out}.body"
  return 0
}

BC="/tmp/spark-bc-emit-hello.sparkbc"
./spark-bc-pack-hello "$BC"
if emit_elf "$BC" hello; then
  echo "PASS bc_emit_hello_elf"
else
  echo "FAIL bc_emit_hello_elf"
  exit 1
fi
rm -f "$BC"

CLS_BC="selfhost/fixtures/classify_dry.sparkbc"
if [[ ! -f "$CLS_BC" ]]; then
  echo "FAIL bc_emit_classify_elf: missing $CLS_BC"
  exit 1
fi
if emit_elf "$CLS_BC" classify; then
  echo "PASS bc_emit_classify_elf"
else
  echo "FAIL bc_emit_classify_elf"
  exit 1
fi

TOOL_BC="selfhost/fixtures/tool_agent.sparkbc"
if [[ ! -f "$TOOL_BC" ]]; then
  echo "FAIL bc_emit_tool_elf: missing $TOOL_BC"
  exit 1
fi
if emit_elf "$TOOL_BC" tool; then
  echo "PASS bc_emit_tool_elf"
else
  echo "FAIL bc_emit_tool_elf"
  exit 1
fi

EXT_BC="selfhost/fixtures/extract_dry.sparkbc"
if [[ ! -f "$EXT_BC" ]]; then
  echo "FAIL bc_emit_extract_elf: missing $EXT_BC"
  exit 1
fi
if emit_elf "$EXT_BC" extract; then
  echo "PASS bc_emit_extract_elf"
else
  echo "FAIL bc_emit_extract_elf"
  exit 1
fi

PIPE_BC="selfhost/fixtures/pipeline_dry.sparkbc"
if [[ ! -f "$PIPE_BC" ]]; then
  echo "FAIL bc_emit_pipeline_elf: missing $PIPE_BC"
  exit 1
fi
if emit_elf "$PIPE_BC" pipeline; then
  echo "PASS bc_emit_pipeline_elf"
else
  echo "FAIL bc_emit_pipeline_elf"
  exit 1
fi

LISTEN_BC="selfhost/fixtures/listen_dry.sparkbc"
if [[ ! -f "$LISTEN_BC" ]]; then
  echo "FAIL bc_emit_listen_elf: missing $LISTEN_BC"
  exit 1
fi
if emit_elf "$LISTEN_BC" listen; then
  echo "PASS bc_emit_listen_elf"
else
  echo "FAIL bc_emit_listen_elf"
  exit 1
fi

SPEAK_BC="selfhost/fixtures/speak_dry.sparkbc"
if [[ ! -f "$SPEAK_BC" ]]; then
  echo "FAIL bc_emit_speak_elf: missing $SPEAK_BC"
  exit 1
fi
if emit_elf "$SPEAK_BC" speak; then
  echo "PASS bc_emit_speak_elf"
else
  echo "FAIL bc_emit_speak_elf"
  exit 1
fi

VOICE_BC="selfhost/fixtures/review_voice.sparkbc"
if [[ ! -f "$VOICE_BC" ]]; then
  echo "FAIL bc_emit_voice_elf: missing $VOICE_BC"
  exit 1
fi
if emit_elf_parity "$VOICE_BC" review_voice; then
  echo "PASS bc_emit_review_voice_elf"
else
  echo "FAIL bc_emit_review_voice_elf"
  exit 1
fi

BROWSER_BC="selfhost/fixtures/browser_dry.sparkbc"
if [[ ! -f "$BROWSER_BC" ]]; then
  echo "FAIL bc_emit_browser_elf: missing $BROWSER_BC"
  exit 1
fi
if emit_elf_parity "$BROWSER_BC" browser_dry; then
  echo "PASS bc_emit_browser_dry_elf"
else
  echo "FAIL bc_emit_browser_dry_elf"
  exit 1
fi

MITM_BC="selfhost/fixtures/mitm_enable.sparkbc"
if [[ ! -f "$MITM_BC" ]]; then
  echo "FAIL bc_emit_mitm_elf: missing $MITM_BC"
  exit 1
fi
if emit_elf_parity "$MITM_BC" mitm_enable; then
  echo "PASS bc_emit_mitm_enable_elf"
else
  echo "FAIL bc_emit_mitm_enable_elf"
  exit 1
fi

if [[ ! -f selfhost/fixtures/engine_dry.spark ]]; then
  echo "FAIL bc_emit_engine_elf: missing engine_dry.spark"
  exit 1
fi
./spark-bootstrap --compile selfhost/fixtures/engine_dry.spark \
  -o selfhost/fixtures/engine_dry.sparkbc
if emit_elf_parity selfhost/fixtures/engine_dry.sparkbc engine_dry; then
  echo "PASS bc_emit_engine_dry_elf"
else
  echo "FAIL bc_emit_engine_dry_elf"
  exit 1
fi


for auto_tag in use_auto_fast use_auto_code; do
  auto_src="selfhost/fixtures/${auto_tag}.spark"
  auto_bc="selfhost/fixtures/${auto_tag}.sparkbc"
  if [[ ! -f "$auto_src" ]]; then
    echo "FAIL bc_emit_${auto_tag}_elf: missing $auto_src"
    exit 1
  fi
  ./spark-bootstrap --compile "$auto_src" -o "$auto_bc" || {
    echo "FAIL bc_emit_${auto_tag}_elf: compile"
    exit 1
  }
  if emit_elf_parity "$auto_bc" "$auto_tag"; then
    echo "PASS bc_emit_${auto_tag}_elf"
  else
    echo "FAIL bc_emit_${auto_tag}_elf"
    exit 1
  fi
done

BRG_BC="selfhost/fixtures/browser_run_goto.sparkbc"
if [[ ! -f "$BRG_BC" ]]; then
  echo "FAIL bc_emit_browser_run_goto_elf: missing $BRG_BC"
  exit 1
fi
if emit_elf_parity "$BRG_BC" browser_run_goto; then
  echo "PASS bc_emit_browser_run_goto_elf"
else
  echo "FAIL bc_emit_browser_run_goto_elf"
  exit 1
fi

if [[ ! -f selfhost/fixtures/ide_dry.spark ]]; then
  echo "FAIL bc_emit_ide_elf: missing ide_dry.spark"
  exit 1
fi
./spark-bootstrap --compile selfhost/fixtures/ide_dry.spark \
  -o selfhost/fixtures/ide_dry.sparkbc
if emit_elf selfhost/fixtures/ide_dry.sparkbc ide_dry; then
  echo "PASS bc_emit_ide_dry_elf"
else
  echo "FAIL bc_emit_ide_dry_elf"
  exit 1
fi

echo "OK bc_emit"
