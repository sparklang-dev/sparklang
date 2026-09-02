#!/usr/bin/env bash
# Shared helpers for Spark runtime installer builders.
set -euo pipefail

INSTALLERS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$INSTALLERS/../.." && pwd)"
KIT="$ROOT/tools/runtime-kit"

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

AI_EXAMPLES=(
  hello.spark
  hello_sugar.spark
  say_sugar.spark
  classify_intent.spark
  extract_person.spark
  pipeline_translate.spark
  ask_live.spark
  ask_probe.spark
  model_improve.spark
  review_builder.spark
  voice_turn.spark
)

copy_ai_examples() {
  local dest="$1"
  mkdir -p "$dest"
  local f
  for f in "${AI_EXAMPLES[@]}"; do
    cp "$ROOT/examples/$f" "$dest/"
  done
}

copy_ai_guides() {
  local dir="$1"
  cp "$KIT/runtime-ai-guide.txt" "$KIT/spark.toml.example" "$dir/"
}

copy_bin_if_exists() {
  local dest="$1"
  shift
  local bin
  for bin in "$@"; do
    if [[ -f "$bin" ]]; then
      cp -a "$bin" "$dest/"
    fi
  done
}

write_spark_run() {
  local dir="$1"
  cat >"$dir/spark-run.sh" <<'RUN'
#!/usr/bin/env bash
# Run spark-bc from bin/ (compile → bc_vm when supported).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT/bin"
runner=./spark-bc
if [[ ! -x "$runner" ]]; then
  runner=./spark-bootstrap
fi
args=()
for a in "$@"; do
  if [[ "$a" == examples/* && -f "$ROOT/$a" ]]; then
    args+=("$ROOT/$a")
  else
    args+=("$a")
  fi
done
exec "$runner" "${args[@]}"
RUN
  chmod +x "$dir/spark-run.sh"
}

stage_linux_full() {
  local dir="$1"
  mkdir -p "$dir/bin" "$dir/examples"
  cp -a "$ROOT/spark-bootstrap" "$dir/bin/"
  if [[ -f "$ROOT/scripts/spark-bc" ]]; then
    cp -a "$ROOT/scripts/spark-bc" "$dir/bin/spark-bc"
    chmod +x "$dir/bin/spark-bc"
    ln -sfn spark-bc "$dir/bin/spark"
  fi
  if [[ -f "$ROOT/spark" ]]; then
    cp -a "$ROOT/spark" "$dir/bin/spark-gas-legacy"
  fi
  copy_bin_if_exists "$dir/bin" \
    "$ROOT/spark-ask-http" \
    "$ROOT/spark-ask-probe" \
    "$ROOT/spark-enc-gateway" \
    "$ROOT/spark-stt-tts" \
    "$ROOT/spark-review-url"
  cp -a "$ROOT/sparkasm/sparkasm" "$dir/bin/"
  copy_ai_examples "$dir/examples"
  copy_ai_guides "$dir"
  write_spark_run "$dir"
  ln -sfn ../examples "$dir/bin/examples"
}

# Linux arm64 hybrid: cross-compiled C bootstrap + companions; no x86_64 ./spark.
stage_linux_arm64_hybrid() {
  local dir="$1"
  local cross_bin="$ROOT/out/cross-arm64/bin"
  mkdir -p "$dir/bin" "$dir/examples"
  if [[ ! -x "$cross_bin/spark-bootstrap" ]]; then
    bash "$INSTALLERS/cross_linux_arm64.sh" "$cross_bin"
  fi
  copy_bin_if_exists "$dir/bin" \
    "$cross_bin/spark-bootstrap" \
    "$cross_bin/sparkasm" \
    "$cross_bin/spark-ask-http" \
    "$cross_bin/spark-ask-probe" \
    "$cross_bin/spark-enc-gateway" \
    "$cross_bin/spark-stt-tts" \
    "$cross_bin/spark-review-url"
  copy_ai_examples "$dir/examples"
  copy_ai_guides "$dir"
  cat >"$dir/spark-run.sh" <<'RUN'
#!/usr/bin/env bash
# arm64 hybrid: spark-bc / spark-bootstrap is the primary VM.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT/bin"
runner=./spark-bc
if [[ ! -x "$runner" ]]; then
  runner=./spark-bootstrap
fi
args=()
for a in "$@"; do
  if [[ "$a" == examples/* && -f "$ROOT/$a" ]]; then
    args+=("$ROOT/$a")
  else
    args+=("$a")
  fi
done
exec "$runner" "${args[@]}"
RUN
  chmod +x "$dir/spark-run.sh"
  if [[ -f "$ROOT/scripts/spark-bc" ]]; then
    cp -a "$ROOT/scripts/spark-bc" "$dir/bin/spark-bc"
    chmod +x "$dir/bin/spark-bc"
    ln -sfn spark-bc "$dir/bin/spark"
  else
    ln -sfn spark-bootstrap "$dir/bin/spark" 2>/dev/null || true
  fi
  ln -sfn ../examples "$dir/bin/examples"
  cat >"$dir/ARCH-NOTES.txt" <<'NOTES'
Linux arm64 hybrid runtime
==========================
Prebuilt (aarch64 ELF):
  spark-bc            product CLI (wrapper → spark-bootstrap)
  spark-bootstrap     primary VM — compile + bc_vm / tree-walk dry-run
  sparkasm            Spark-native assembler
  spark-ask-http, spark-ask-probe, spark-stt-tts, spark-review-url (when built)

Not included:
  spark-gas-legacy (x86_64 GAS assembly VM) — requires a future arm64 asm port.
  spark-enc-gateway — needs arm64 OpenSSL dev (not on build host).

Bootstrap uses portable C engine stubs for layout/paint on arm64 (engine
browser ops fail loud until arm64 asm lands).
NOTES
}

# Map uname -m style names to manifest arch labels.
normalize_arch() {
  case "$1" in
    x86_64|amd64) echo "x86_64" ;;
    aarch64|arm64) echo "arm64" ;;
    i686|i386|x86) echo "i686" ;;
    *) echo "$1" ;;
  esac
}

deb_arch_for() {
  case "$(normalize_arch "$1")" in
    x86_64) echo "amd64" ;;
    arm64) echo "arm64" ;;
    i686) echo "i386" ;;
    *) echo "$1" ;;
  esac
}

stage_portable_kit() {
  local os="$1"
  local dir="$2"
  local arch="${3:-}"
  mkdir -p "$dir/bin" "$dir/examples" "$dir/src/bootstrap" "$dir/src/sparkasm"
  cp "$ROOT/bootstrap/"*.c "$ROOT/bootstrap/"*.h "$dir/src/bootstrap/"
  cp "$KIT/bootstrap/Makefile" "$dir/src/bootstrap/Makefile"
  cp -a \
    "$ROOT/sparkasm/src" \
    "$ROOT/sparkasm/include" \
    "$ROOT/sparkasm/Makefile" \
    "$ROOT/sparkasm/fixtures" \
    "$dir/src/sparkasm/"
  copy_ai_examples "$dir/examples"
  copy_ai_guides "$dir"
  if [[ -f "$ROOT/scripts/spark-bc" ]]; then
    mkdir -p "$dir/bin" "$dir/scripts"
    cp -a "$ROOT/scripts/spark-bc" "$dir/scripts/spark-bc"
    cp -a "$ROOT/scripts/spark-bc" "$dir/bin/spark-bc"
    chmod +x "$dir/scripts/spark-bc" "$dir/bin/spark-bc"
  fi
  write_spark_run "$dir"

  cat >"$dir/build.sh" <<'BUILD'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
make -C src/bootstrap spark-bootstrap
make -C src/sparkasm
mkdir -p bin
cp src/bootstrap/spark-bootstrap src/sparkasm/sparkasm bin/
if [[ -x scripts/spark-bc ]]; then
  cp scripts/spark-bc bin/
  chmod +x bin/spark-bc
fi
echo "Built bin/spark-bootstrap and bin/sparkasm"
echo "Product CLI:"
echo "  ./bin/spark-bc examples/hello.spark"
echo "  ./bin/spark-bootstrap --dry-run examples/classify_intent.spark"
BUILD
  chmod +x "$dir/build.sh"

  if [[ -n "$arch" ]]; then
    echo "$arch" >"$dir/.spark-target-arch"
  fi

  if [[ "$os" == "windows" ]]; then
    cat >"$dir/build.bat" <<'BAT'
@echo off
setlocal
cd /d "%~dp0"
where bash >nul 2>&1
if errorlevel 1 (
  echo Git Bash or WSL required to compile Spark bootstrap on Windows.
  echo Install Git for Windows, then run: bash build.sh
  exit /b 1
)
bash build.sh
BAT
  fi
}
