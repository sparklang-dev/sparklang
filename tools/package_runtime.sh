#!/usr/bin/env bash
# Package Spark runtime libraries + per-OS/per-CPU installers for sparklang.dev.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALLERS="$ROOT/tools/installers"
cd "$ROOT"

VERSION="$(./spark --version 2>/dev/null | awk '{print $2}' \
  || ./spark-bootstrap --version 2>/dev/null | awk '{print $2}' \
  || echo "0.6.0")"
OUT="$ROOT/website/downloads"
STAGE="$ROOT/out/runtime-pack"
MANIFEST="$OUT/manifest.json"
DOWNLOAD_BASE="https://sparklang.dev/downloads"

# shellcheck source=installers/common.sh
source "$INSTALLERS/common.sh"

mkdir -p "$OUT"
rm -rf "$STAGE"
mkdir -p "$STAGE"

echo "==> Toolchain probe"
# shellcheck disable=SC1090
source <(bash "$INSTALLERS/probe_toolchains.sh" | sed 's/^/export /')
bash "$INSTALLERS/probe_toolchains.sh"

echo "==> Building Spark BC product + legacy GAS + AI companions"
make -q spark companions spark-bootstrap spark-bc sparkasm 2>/dev/null || {
  make spark companions spark-bootstrap spark-bc sparkasm
}

SOURCE_KIT_INCLUDES='[
        "spark-bootstrap",
        "sparkasm",
        "scripts/spark-bc",
        "ai-examples",
        "build.sh",
        "spark-run.sh",
        "runtime-ai-guide.txt",
        "spark.toml.example"
      ]'

PREBUILT_INCLUDES='[
        "spark-bc",
        "spark-bootstrap",
        "spark-gas-legacy",
        "spark-ask-http",
        "spark-ask-probe",
        "spark-enc-gateway",
        "spark-stt-tts",
        "spark-review-url",
        "sparkasm",
        "ai-examples",
        "spark-run.sh",
        "runtime-ai-guide.txt",
        "spark.toml.example"
      ]'

HYBRID_ARM64_INCLUDES='[
        "spark-bc",
        "spark-bootstrap",
        "spark-ask-http",
        "spark-ask-probe",
        "spark-stt-tts",
        "spark-review-url",
        "sparkasm",
        "ai-examples",
        "spark-run.sh",
        "runtime-ai-guide.txt",
        "spark.toml.example",
        "ARCH-NOTES.txt"
      ]'

write_ai_readme_linux_prebuilt() {
  local dir="$1" name="$2" arch="$3"
  cat >"$dir/README.txt" <<EOF
Spark AI runtime — Linux ${arch} (${VERSION}) — prebuilt
========================================================

AI-first language runtime: ask, classify, extract, pipeline, model analyze,
review, voice, and encrypt-to-model gateway — in one reviewable .spark file.

Primary CLI: spark-bc (compile → bc_vm when supported) via spark-bootstrap.
Legacy GAS assembly VM: bin/spark-gas-legacy (x86_64 compare / --live only).

Quick start (dry-run, no network)
---------------------------------
  tar xzf ${name}.tar.gz
  cd ${name}
  ./bin/spark-bc examples/hello.spark
  ./bin/spark-gas-legacy --dry-run examples/hello.spark   # legacy compare

Installers: spark-runtime-linux-${arch}-${VERSION}.deb
Docs: https://sparklang.dev/docs/programming-guide.html
EOF
}

write_ai_readme_linux_source() {
  local dir="$1" name="$2" arch="$3"
  cat >"$dir/README.txt" <<EOF
Spark AI runtime — Linux ${arch} (${VERSION}) — source kit
==========================================================

Bootstrap + sparkasm compile on your ${arch} machine (build.sh).
Nine AI examples + runtime-ai-guide.txt included.

  tar xzf ${name}.tar.gz
  cd ${name}
  ./build.sh
  ./bin/spark-bc examples/hello.spark

For prebuilt spark-bc + legacy GAS + full AI companions, use Linux x86_64.
Docs: https://sparklang.dev/docs/programming-guide.html
EOF
}

pack_linux_x86_64() {
  local arch="x86_64"
  local name="spark-runtime-linux-${arch}-${VERSION}"
  local dir="$STAGE/$name"
  stage_linux_full "$dir"
  write_ai_readme_linux_prebuilt "$dir" "$name" "$arch"
  tar -C "$STAGE" -czf "$OUT/${name}.tar.gz" "$name"
  "$INSTALLERS/build_linux_deb.sh" "$VERSION" "$STAGE" "$OUT" "$arch" prebuilt
}

write_ai_readme_linux_hybrid() {
  local dir="$1" name="$2" arch="$3"
  cat >"$dir/README.txt" <<EOF
Spark AI runtime — Linux ${arch} (${VERSION}) — hybrid prebuilt
================================================================

Prebuilt aarch64 ELF: spark-bc (product CLI), spark-bootstrap (primary VM),
sparkasm, and C AI companions (ask-http, ask-probe, stt-tts, review-url).
spark-gas-legacy (x86_64 GAS asm VM) is not included — use spark-bc for dry-run.

Quick start (dry-run, no network)
---------------------------------
  sudo dpkg -i ${name}.deb
  spark-bc /opt/spark/examples/hello.spark

Or tarball:
  tar xzf ${name}.tar.gz && cd ${name}
  ./bin/spark-bc examples/hello.spark

Docs: https://sparklang.dev/docs/programming-guide.html
EOF
}

pack_linux_arm64_hybrid() {
  local arch="arm64"
  local name="spark-runtime-linux-${arch}-${VERSION}"
  local dir="$STAGE/$name"
  stage_linux_arm64_hybrid "$dir"
  write_ai_readme_linux_hybrid "$dir" "$name" "$arch"
  tar -C "$STAGE" -czf "$OUT/${name}.tar.gz" "$name"
  "$INSTALLERS/build_linux_deb.sh" "$VERSION" "$STAGE" "$OUT" "$arch" hybrid
  rm -rf "$dir"
}

pack_linux_arm64_source() {
  local arch="arm64"
  local name="spark-runtime-linux-${arch}-${VERSION}-source"
  local dir="$STAGE/$name"
  stage_portable_kit linux "$dir" "$arch"
  write_ai_readme_linux_source "$dir" "$name" "$arch"
  tar -C "$STAGE" -czf "$OUT/${name}.tar.gz" "$name"
  rm -rf "$dir"
}

pack_portable_tar() {
  local os="$1" arch="$2"
  local name="spark-runtime-${os}-${arch}-${VERSION}"
  local dir="$STAGE/$name"
  stage_portable_kit "$os" "$dir" "$arch"
  cat >"$dir/README.txt" <<EOF
Spark AI portable runtime kit — ${os} ${arch} (${VERSION})
==========================================================

Build bootstrap VM and sparkasm on your machine, then dry-run AI examples.

  tar xzf ${name}.tar.gz && cd ${name} && ./build.sh
Docs: https://sparklang.dev/docs/programming-guide.html
EOF
  tar -C "$STAGE" -czf "$OUT/${name}.tar.gz" "$name"
  rm -rf "$dir"
}

sha256() {
  sha256sum "$1" | awk '{print $1}'
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

PLATFORM_JSON=""
append_platform() {
  local json="$1"
  if [[ -n "$PLATFORM_JSON" ]]; then
    PLATFORM_JSON="${PLATFORM_JSON},"
  fi
  PLATFORM_JSON="${PLATFORM_JSON}${json}"
}

add_if_file() {
  local os="$1" arch="$2" label="$3" kind="$4" format="$5" file="$6"
  local primary="${7:-false}" notes="${8:-}" graphical="${9:-false}" includes="${10:-}"
  [[ -f "$OUT/$file" ]] || return 0
  local inc=""
  if [[ -n "$includes" ]]; then
    inc=", \"includes\": ${includes}"
  fi
  append_platform "$(cat <<EOF
    {
      "os": "${os}",
      "arch": "${arch}",
      "id": "${os}-${arch}",
      "label": "$(json_escape "$label")",
      "kind": "${kind}",
      "format": "${format}",
      "file": "${file}",
      "sha256": "$(sha256 "$OUT/$file")",
      "primary": ${primary},
      "graphical": ${graphical},
      "notes": "$(json_escape "$notes")"${inc}
    }
EOF
)"
}

echo "==> Linux x86_64 (prebuilt)"
pack_linux_x86_64

if [[ "${aarch64_linux_gcc:-no}" == "yes" ]]; then
  echo "==> Linux arm64 (hybrid prebuilt — bootstrap + C companions)"
  pack_linux_arm64_hybrid
  echo "==> Linux arm64 (source kit tarball)"
  pack_linux_arm64_source
else
  echo "==> Linux arm64 (source kit — no aarch64-linux-gnu-gcc)"
  pack_linux_arm64_source
fi

echo "==> macOS per CPU"
for mac_arch in arm64 x86_64; do
  "$INSTALLERS/build_macos_pkg.sh" "$VERSION" "$STAGE" "$OUT" "$mac_arch"
  pack_portable_tar macos "$mac_arch"
done

echo "==> Windows per CPU"
for win_arch in x86_64 arm64; do
  "$INSTALLERS/build_windows_installer.sh" "$VERSION" "$STAGE" "$OUT" "$win_arch"
done

echo "==> curl|bash + graphical installers"
chmod +x "$INSTALLERS"/*.sh
"$INSTALLERS/build_linux_install.sh" "$VERSION" "$DOWNLOAD_BASE" "$OUT"
GUI_OUT="$OUT/spark-install-linux-gui.sh"
sed "s/^VERSION=.*/VERSION=\"${VERSION}\"/" "$INSTALLERS/spark-install-gui.sh" >"$GUI_OUT"
chmod +x "$GUI_OUT"
echo "Wrote $GUI_OUT"

cat >"$OUT/spark-install-macos.sh" <<EOF
#!/usr/bin/env bash
# Spark AI runtime installer — macOS (auto-detect arm64 vs x86_64)
set -euo pipefail
VERSION="${VERSION}"
BASE="${DOWNLOAD_BASE}"
case "\$(uname -m)" in
  arm64|aarch64) ARCH=arm64 ;;
  x86_64) ARCH=x86_64 ;;
  *) echo "Unsupported Mac CPU: \$(uname -m)" >&2; exit 1 ;;
esac
PKG="spark-runtime-macos-\${ARCH}-\${VERSION}.pkg"
tmpdir="\$(mktemp -d)"
trap 'rm -rf "\$tmpdir"' EXIT
echo "==> Downloading \${PKG} for \${ARCH}"
curl -fsSL "\${BASE}/\${PKG}" -o "\$tmpdir/\${PKG}"
echo "==> Installing (may prompt for password)"
sudo installer -pkg "\$tmpdir/\${PKG}" -target /
echo "Done. Try: /usr/local/spark/bin/spark-bc /usr/local/spark/examples/hello.spark"
EOF
chmod +x "$OUT/spark-install-macos.sh"

V="$VERSION"
# Linux x86_64
add_if_file linux x86_64 "Linux x86_64" installer deb \
  "spark-runtime-linux-x86_64-${V}.deb" true \
  "Graphical: .deb — spark-bc primary; spark-gas-legacy secondary" \
  true "$PREBUILT_INCLUDES"
add_if_file linux x86_64 "Linux x86_64" installer gui-script \
  "spark-install-linux-gui.sh" false \
  "zenity/yad wizard — download + install .deb with progress bar" true
add_if_file linux x86_64 "Linux x86_64" installer curl-bash \
  "spark-install-linux.sh" false \
  "CLI fallback — auto-detects CPU; prefers .deb with root" false
add_if_file linux x86_64 "Linux x86_64" binary tar.gz \
  "spark-runtime-linux-x86_64-${V}.tar.gz" false \
  "Prebuilt tarball — spark-bc primary, spark-gas-legacy secondary" false \
  "$PREBUILT_INCLUDES"

# Linux arm64
if [[ "${aarch64_linux_gcc:-no}" == "yes" ]]; then
  add_if_file linux arm64 "Linux arm64 (aarch64)" installer deb \
    "spark-runtime-linux-arm64-${V}.deb" true \
    "Graphical .deb — hybrid prebuilt bootstrap+companions; spark asm VM pending arm64 port" \
    true "$HYBRID_ARM64_INCLUDES"
  add_if_file linux arm64 "Linux arm64 (aarch64)" hybrid tar.gz \
    "spark-runtime-linux-arm64-${V}.tar.gz" false \
    "Hybrid prebuilt tarball (spark-bc / spark-bootstrap primary)" false \
    "$HYBRID_ARM64_INCLUDES"
  add_if_file linux arm64 "Linux arm64 (aarch64)" source-kit tar.gz \
    "spark-runtime-linux-arm64-${V}-source.tar.gz" false \
    "Full source kit — compile bootstrap+sparkasm locally" false "$SOURCE_KIT_INCLUDES"
else
  add_if_file linux arm64 "Linux arm64 (aarch64)" installer deb \
    "spark-runtime-linux-arm64-${V}.deb" true \
    "Graphical .deb — source kit; build.sh on first install (postinst)" \
    true "$SOURCE_KIT_INCLUDES"
  add_if_file linux arm64 "Linux arm64 (aarch64)" source-kit tar.gz \
    "spark-runtime-linux-arm64-${V}.tar.gz" false \
    "Bootstrap + sparkasm; compiles natively on arm64" false "$SOURCE_KIT_INCLUDES"
fi

# macOS
for ma in arm64 x86_64; do
  lbl="macOS ${ma}"
  [[ "$ma" == "arm64" ]] && lbl="macOS Apple Silicon (arm64)"
  [[ "$ma" == "x86_64" ]] && lbl="macOS Intel (x86_64)"
  pri=false
  [[ "$ma" == "arm64" ]] && pri=true
  add_if_file macos "$ma" "$lbl" installer pkg \
    "spark-runtime-macos-${ma}-${V}.pkg" "$pri" \
    "Graphical .pkg — double-click in Finder; welcome + conclusion pages" \
    true "$SOURCE_KIT_INCLUDES"
  add_if_file macos "$ma" "$lbl" source-kit tar.gz \
    "spark-runtime-macos-${ma}-${V}.tar.gz" false \
    "Portable source kit tarball (manual)" false "$SOURCE_KIT_INCLUDES"
done
add_if_file macos arm64 "macOS (auto)" installer curl-bash \
  "spark-install-macos.sh" false \
  "CLI fallback — picks arm64 or x86_64 .pkg from uname -m" false

# Windows
for wa in x86_64 arm64; do
  wl="Windows x64"
  [[ "$wa" == "arm64" ]] && wl="Windows arm64"
  pri=false
  [[ "$wa" == "x86_64" ]] && pri=true
  exe="spark-runtime-windows-${wa}-${V}-setup.exe"
  zip="spark-runtime-windows-${wa}-${V}-setup.zip"
  if [[ -f "$OUT/$exe" ]]; then
    add_if_file windows "$wa" "$wl" installer inno-exe "$exe" "$pri" \
      "Graphical Inno Setup wizard — install dir, PATH option, first-run build" \
      true "$SOURCE_KIT_INCLUDES"
    if [[ -f "$OUT/$zip" ]]; then
      add_if_file windows "$wa" "$wl" installer zip "$zip" false \
        "CLI fallback — extract zip, run Setup.bat (needs Git Bash + gcc)" \
        false "$SOURCE_KIT_INCLUDES"
    fi
  else
    add_if_file windows "$wa" "$wl" installer zip "$zip" "$pri" \
      "CLI fallback — extract zip, run Setup.bat (needs Git Bash + gcc)" \
      false "$SOURCE_KIT_INCLUDES"
  fi
done

SKIPPED_JSON='[
    {
      "os": "linux",
      "arch": "i686",
      "reason": "32-bit Linux (i686) is not offered — Spark core targets 64-bit x86. Use x86_64 or build from source."
    }
  ]'

cat >"$MANIFEST" <<EOF
{
  "version": "${VERSION}",
  "updated": "$(date -u +%Y-%m-%dT%H:%MZ)",
  "build_host": {
    "arch": "${host_arch:-unknown}",
    "spark_prebuilt_linux": "${spark_prebuilt_linux:-unknown}",
    "aarch64_linux_gcc": "${aarch64_linux_gcc:-unknown}",
    "x86_64_mingw_gcc": "${x86_64_mingw_gcc:-unknown}",
    "aarch64_mingw_gcc": "${aarch64_mingw_gcc:-unknown}"
  },
  "skipped": ${SKIPPED_JSON},
  "platforms": [
${PLATFORM_JSON}
  ]
}
EOF

echo "==> Wrote $MANIFEST"
ls -lh "$OUT"
