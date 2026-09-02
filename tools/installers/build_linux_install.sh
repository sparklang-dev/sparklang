#!/usr/bin/env bash
# Emit curl|bash friendly spark-install-linux.sh (arch-aware via uname -m).
set -euo pipefail

INSTALLERS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$INSTALLERS/common.sh"

VERSION="${1:?usage: build_linux_install.sh VERSION DOWNLOAD_BASE OUT_DIR}"
DOWNLOAD_BASE="${2:?}"
OUT_DIR="${3:?}"

SCRIPT="$OUT_DIR/spark-install-linux.sh"

cat >"$SCRIPT" <<'EOF'
#!/usr/bin/env bash
# Spark AI runtime installer — Linux (auto-detect CPU via uname -m)
# Usage: curl -fsSL https://sparklang.dev/downloads/spark-install-linux.sh | bash
# User install (no root): curl -fsSL ... | bash -s -- --user
set -euo pipefail

VERSION="__VERSION__"
DOWNLOAD_BASE="__DOWNLOAD_BASE__"
MODE="system"

normalize_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "x86_64" ;;
    aarch64|arm64) echo "arm64" ;;
    i686|i386|x86) echo "i686" ;;
    *) echo "$(uname -m)" ;;
  esac
}

ARCH="$(normalize_arch)"
TARBALL="spark-runtime-linux-${ARCH}-${VERSION}.tar.gz"
DEB="spark-runtime-linux-${ARCH}-${VERSION}.deb"

usage() {
  cat <<USAGE
Spark runtime installer ${VERSION} (Linux ${ARCH})

  curl -fsSL https://sparklang.dev/downloads/spark-install-linux.sh | bash
  curl -fsSL ... | bash -s -- --user          # install to ~/.local/spark
  curl -fsSL ... | bash -s -- --prefix /opt/spark

x86_64: prebuilt spark-bc + spark-bootstrap; spark-gas-legacy secondary.
arm64: hybrid prebuilt (spark-bc + spark-bootstrap + companions).
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) MODE="user"; shift ;;
    --prefix) SPARK_PREFIX="$2"; MODE="custom"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ "$ARCH" == "i686" ]]; then
  echo "Spark runtime: 32-bit Linux (i686) is not published — build from source." >&2
  echo "See https://sparklang.dev/downloads/manifest.json" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "==> Detected Linux ${ARCH}"
echo "==> Downloading ${TARBALL}"
curl -fsSL "${DOWNLOAD_BASE}/${TARBALL}" -o "$tmpdir/${TARBALL}"
echo "==> Extracting"
tar -C "$tmpdir" -xzf "$tmpdir/${TARBALL}"
srcdir="$tmpdir/spark-runtime-linux-${ARCH}-${VERSION}"

if [[ ! -d "$srcdir" ]]; then
  echo "Extract failed — expected $srcdir" >&2
  exit 1
fi

if [[ "$MODE" == "user" ]]; then
  SPARK_PREFIX="${HOME}/.local/spark"
  bindir="${HOME}/.local/bin"
  mkdir -p "$SPARK_PREFIX" "$bindir"
  cp -a "$srcdir/bin" "$srcdir/examples" "$srcdir/runtime-ai-guide.txt" \
    "$srcdir/spark.toml.example" "$SPARK_PREFIX/"
  [[ -f "$srcdir/spark-run.sh" ]] && cp "$srcdir/spark-run.sh" "$SPARK_PREFIX/"
  [[ -f "$srcdir/build.sh" ]] && cp "$srcdir/build.sh" "$SPARK_PREFIX/" && \
    (cd "$SPARK_PREFIX" && ./build.sh)
  for b in "$SPARK_PREFIX/bin/"*; do
    [[ -x "$b" ]] || continue
    ln -sf "$b" "$bindir/$(basename "$b")"
  done
  echo "Installed to $SPARK_PREFIX (symlinks in $bindir)"
  runner="spark-bc"
  [[ -x "$SPARK_PREFIX/bin/spark-bc" ]] || runner="spark-bootstrap"
  echo "Try: $runner $SPARK_PREFIX/examples/hello.spark"
elif [[ "$MODE" == "custom" ]]; then
  mkdir -p "$SPARK_PREFIX/bin" "$SPARK_PREFIX/examples"
  cp -a "$srcdir/"* "$SPARK_PREFIX/"
  [[ -x "$SPARK_PREFIX/build.sh" ]] && (cd "$SPARK_PREFIX" && ./build.sh)
  echo "Installed to $SPARK_PREFIX"
else
  if command -v dpkg >/dev/null 2>&1 && [[ $(id -u) -eq 0 ]]; then
    curl -fsSL "${DOWNLOAD_BASE}/${DEB}" -o "$tmpdir/${DEB}" || true
    if [[ -f "$tmpdir/${DEB}" ]]; then
      dpkg -i "$tmpdir/${DEB}" || apt-get install -f -y
      echo "Installed via .deb to /opt/spark"
      exit 0
    fi
  fi
  SPARK_PREFIX="/opt/spark"
  if [[ $(id -u) -ne 0 ]]; then
    echo "System install needs root (sudo) or use --user" >&2
    exit 1
  fi
  mkdir -p "$SPARK_PREFIX" /usr/local/bin
  cp -a "$srcdir/"* "$SPARK_PREFIX/"
  [[ -x "$SPARK_PREFIX/build.sh" ]] && (cd "$SPARK_PREFIX" && ./build.sh)
  for b in "$SPARK_PREFIX/bin/"*; do
    [[ -x "$b" ]] || continue
    ln -sf "$b" "/usr/local/bin/$(basename "$b")"
  done
  echo "Installed to $SPARK_PREFIX (symlinks in /usr/local/bin)"
fi
EOF

sed -i "s|__VERSION__|${VERSION}|g; s|__DOWNLOAD_BASE__|${DOWNLOAD_BASE}|g" "$SCRIPT"
chmod +x "$SCRIPT"
echo "Wrote $SCRIPT"
