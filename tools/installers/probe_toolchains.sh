#!/usr/bin/env bash
# Report cross-compile toolchains available on this build host.
set -euo pipefail

probe_cmd() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    echo "yes"
  else
    echo "no"
  fi
}

HOST_ARCH="$(uname -m)"
NATIVE_GCC="$(probe_cmd "${CC:-cc}")"
AARCH64_LINUX_GCC="$(probe_cmd aarch64-linux-gnu-gcc)"
I686_LINUX_GCC="$(probe_cmd i686-linux-gnu-gcc)"
X86_64_MINGW_GCC="$(probe_cmd x86_64-w64-mingw32-gcc)"
AARCH64_MINGW_GCC="$(probe_cmd aarch64-w64-mingw32-gcc)"
ISCC="no"
if bash "$(dirname "$0")/locate_iscc.sh" >/dev/null 2>&1; then
  ISCC="yes"
fi
PKGBUILD="$(probe_cmd pkgbuild)"

# Spark ./spark is x86_64 Linux assembly — only native x86_64 gets prebuilt ELF.
SPARK_PREBUILT_LINUX="no"
if [[ "$HOST_ARCH" == "x86_64" ]]; then
  SPARK_PREBUILT_LINUX="yes"
fi

cat <<EOF
host_arch=${HOST_ARCH}
native_gcc=${NATIVE_GCC}
aarch64_linux_gcc=${AARCH64_LINUX_GCC}
i686_linux_gcc=${I686_LINUX_GCC}
x86_64_mingw_gcc=${X86_64_MINGW_GCC}
aarch64_mingw_gcc=${AARCH64_MINGW_GCC}
iscc=${ISCC}
pkgbuild=${PKGBUILD}
spark_prebuilt_linux=${SPARK_PREBUILT_LINUX}
EOF
