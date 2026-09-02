#!/usr/bin/env bash
# Cross-compile portable C companions for Linux arm64 (aarch64).
# The main ./spark ELF remains x86_64 GAS-only — not produced here.
set -euo pipefail

INSTALLERS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$INSTALLERS/../.." && pwd)"
OUT="${1:-$ROOT/out/cross-arm64/bin}"

if ! command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
  echo "cross_linux_arm64: aarch64-linux-gnu-gcc not found" >&2
  exit 1
fi

CC=aarch64-linux-gnu-gcc
export CC
CFLAGS=(-O2 -Wall -Wextra -I"$ROOT")
mkdir -p "$OUT"

echo "==> cross arm64: spark-bootstrap (portable C + engine stubs)"
$CC "${CFLAGS[@]}" -o "$OUT/spark-bootstrap" \
  "$ROOT/bootstrap/main.c" \
  "$ROOT/bootstrap/vm.c" \
  "$ROOT/bootstrap/engine_parse.c" \
  "$ROOT/bootstrap/engine_css.c" \
  "$ROOT/bootstrap/engine_layout.c" \
  "$ROOT/bootstrap/engine_paint.c" \
  "$ROOT/bootstrap/engine_show.c" \
  "$ROOT/bootstrap/engine_render.c" \
  "$ROOT/bootstrap/dry_ask.c" \
  "$ROOT/bootstrap/dry_auto_model.c" \
  "$ROOT/bootstrap/dry_classify.c" \
  "$ROOT/bootstrap/dry_rag.c" \
  "$ROOT/bootstrap/dry_http.c" \
  "$ROOT/bootstrap/dry_engine.c" \
  "$ROOT/bootstrap/dry_ide.c" \
  "$ROOT/bootstrap/dry_ops.c" \
  "$ROOT/bootstrap/bc_read.c" \
  "$ROOT/bootstrap/bc_vm.c" \
  "$ROOT/bootstrap/bc_write.c" \
  "$ROOT/bootstrap/spark_parse.c" \
  "$ROOT/selfhost/lex.c" \
  "$ROOT/bootstrap/engine_stubs_portable.c"

echo "==> cross arm64: sparkasm"
$CC "${CFLAGS[@]}" -std=c11 -I"$ROOT/sparkasm/include" \
  -o "$OUT/sparkasm" \
  "$ROOT/sparkasm/src/main.c" \
  "$ROOT/sparkasm/src/sparkasm.c"

echo "==> cross arm64: spark-ask-http spark-http spark-ask-probe spark-stt-tts spark-review-url"
$CC "${CFLAGS[@]}" -o "$OUT/spark-ask-http" \
  "$ROOT/tools/ask/spark_ask_http.c" \
  "$ROOT/bootstrap/dry_auto_model.c"
$CC "${CFLAGS[@]}" -o "$OUT/spark-http" \
  "$ROOT/tools/http/spark_http.c" \
  "$ROOT/bootstrap/dry_http.c"
$CC "${CFLAGS[@]}" -o "$OUT/spark-ask-probe" "$ROOT/tools/ask/spark_ask_probe.c"
$CC "${CFLAGS[@]}" -o "$OUT/spark-stt-tts" "$ROOT/tools/voice/spark_stt_tts.c" -lm
$CC "${CFLAGS[@]}" -o "$OUT/spark-review-url" "$ROOT/tools/review/spark_review_url.c"

if pkg-config --exists openssl 2>/dev/null \
  && aarch64-linux-gnu-gcc -print-sysroot 2>/dev/null | grep -q .; then
  SYSROOT="$(aarch64-linux-gnu-gcc -print-sysroot)"
  if [[ -f "$SYSROOT/usr/include/openssl/evp.h" ]]; then
    echo "==> cross arm64: spark-enc-gateway (sysroot OpenSSL)"
    $CC "${CFLAGS[@]}" -o "$OUT/spark-enc-gateway" \
      "$ROOT/tools/crypto/spark_enc_gateway.c" \
      -I"$SYSROOT/usr/include" -L"$SYSROOT/usr/lib/aarch64-linux-gnu" \
      -lssl -lcrypto || true
  fi
fi

if [[ ! -x "$OUT/spark-enc-gateway" ]]; then
  echo "==> cross arm64: spark-enc-gateway skipped (no arm64 OpenSSL sysroot)"
fi

echo "==> cross arm64 binaries in $OUT"
file "$OUT"/* | sed 's/^/  /'
