#!/usr/bin/env bash
# Graphical Spark installer for Linux — zenity/yad wizard with progress bar.
# Bundled in .deb at /opt/spark/bin/spark-install-gui; also shipped standalone.
set -euo pipefail

VERSION="0.6.0"
DOWNLOAD_BASE="${SPARK_DOWNLOAD_BASE:-https://sparklang.dev/downloads}"
PREFIX="${SPARK_PREFIX:-/opt/spark}"
DEB_NAME=""
ARCH=""

die_gui() {
  local msg="$1"
  if command -v zenity >/dev/null 2>&1; then
    zenity --error --title="Spark install" --text="$msg" --width=420 2>/dev/null || true
  elif command -v yad >/dev/null 2>&1; then
    yad --error --title="Spark install" --text="$msg" --width=420 2>/dev/null || true
  else
    echo "ERROR: $msg" >&2
  fi
  exit 1
}

pick_arch() {
  case "$(uname -m)" in
    x86_64|amd64) ARCH=x86_64 ;;
    aarch64|arm64) ARCH=arm64 ;;
    *)
      die_gui "Unsupported CPU: $(uname -m). Use spark-install-linux.sh instead."
      ;;
  esac
  DEB_NAME="spark-runtime-linux-${ARCH}-${VERSION}.deb"
}

need_gui() {
  if command -v zenity >/dev/null 2>&1; then
    GUI=zenity
  elif command -v yad >/dev/null 2>&1; then
    GUI=yad
  else
    die_gui "Install zenity or yad for the graphical installer, or use:\n  curl -fsSL ${DOWNLOAD_BASE}/spark-install-linux.sh | bash"
  fi
}

gui_question() {
  local title="$1" text="$2"
  if [[ "$GUI" == zenity ]]; then
    zenity --question --title="$title" --text="$text" --width=460 \
      --ok-label="Install" --cancel-label="Cancel" 2>/dev/null
  else
    yad --question --title="$title" --text="$text" --width=460 \
      --button="Install:0" --button="Cancel:1" 2>/dev/null
  fi
}

gui_progress() {
  local title="$1"
  if [[ "$GUI" == zenity ]]; then
    zenity --progress --title="$title" --text="Starting…" --pulsate --auto-close \
      --no-cancel --width=420 2>/dev/null
  else
    yad --progress --title="$title" --text="Starting…" --pulsate --auto-close \
      --no-cancel --width=420 2>/dev/null
  fi
}

gui_info() {
  local title="$1" text="$2"
  if [[ "$GUI" == zenity ]]; then
    zenity --info --title="$title" --text="$text" --width=480 2>/dev/null
  else
    yad --info --title="$title" --text="$text" --width=480 2>/dev/null
  fi
}

run_with_progress() {
  local title="$1"
  shift
  local fifo progress_pid
  fifo="$(mktemp -u)"
  mkfifo "$fifo"
  gui_progress "$title" <"$fifo" &
  progress_pid=$!
  {
    "$@" 2>&1 | while IFS= read -r line; do
      echo "# $line"
      echo "$line"
    done
    echo 100
  } >"$fifo"
  wait "$progress_pid" || true
  rm -f "$fifo"
}

install_deb() {
  local deb="$1"
  if [[ $(id -u) -ne 0 ]]; then
    if command -v pkexec >/dev/null 2>&1; then
      pkexec dpkg -i "$deb"
      pkexec apt-get install -f -y 2>/dev/null || true
    else
      sudo dpkg -i "$deb"
      sudo apt-get install -f -y 2>/dev/null || true
    fi
  else
    dpkg -i "$deb"
    apt-get install -f -y 2>/dev/null || true
  fi
}

main() {
  need_gui
  pick_arch

  local blurb
  blurb="Install Spark AI runtime ${VERSION} for Linux ${ARCH}?

Includes bootstrap VM, sparkasm, and nine AI example programs.
Dry-run offline; live ask via OpenAI-compatible APIs."

  gui_question "Install Spark" "$blurb" || exit 0

  local tmpdir deb url
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  deb="$tmpdir/$DEB_NAME"
  url="${DOWNLOAD_BASE}/${DEB_NAME}"

  if [[ -f "/usr/share/spark-installer/${DEB_NAME}" ]]; then
    cp "/usr/share/spark-installer/${DEB_NAME}" "$deb"
  elif [[ -n "${SPARK_LOCAL_DEB:-}" && -f "$SPARK_LOCAL_DEB" ]]; then
    cp "$SPARK_LOCAL_DEB" "$deb"
  else
    run_with_progress "Downloading Spark" curl -fsSL "$url" -o "$deb"
  fi

  run_with_progress "Installing Spark" install_deb "$deb"

  local path_note=""
  if ! echo "$PATH" | grep -q '/usr/local/bin'; then
    if gui_question "Add to PATH?" \
      "Add /usr/local/bin to your PATH?\n(Spark commands are symlinked there after .deb install)"; then
      path_note="\n\nAdd to ~/.bashrc:\n  export PATH=\"/usr/local/bin:\$PATH\""
    fi
  fi

  gui_info "Spark installed" \
    "Spark ${VERSION} (${ARCH}) is ready at ${PREFIX}.${path_note}

Try:
  spark --dry-run ${PREFIX}/examples/hello.spark

Docs: https://sparklang.dev/docs/programming-guide.html"
}

main "$@"
