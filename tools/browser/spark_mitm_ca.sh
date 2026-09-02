#!/usr/bin/env bash
# Spark companion: fork target for `mitm ca-init|ca-install|ca-status`.
# Crypto lives in spark-browser.mitm.ca — Python is the helper only;
# language SoT remains .spark + asm/browser_ops.s.
# Trust install is NEVER auto — only `--install` (asm gates with --live).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
if [[ -d "$HERE/../spark-browser" ]]; then
  SPARK_ROOT="$HERE"
elif [[ -d "$HERE/../../spark-browser" ]]; then
  SPARK_ROOT="$(cd "$HERE/../.." && pwd)"
else
  echo "error: cannot find spark-browser next to spark/" >&2
  exit 1
fi

BROWSER="$(cd "$SPARK_ROOT/../spark-browser" && pwd)"
PY="$BROWSER/.venv/bin/python"
if [[ ! -x "$PY" ]]; then
  PY=python3
fi
export PYTHONPATH="$BROWSER${PYTHONPATH:+:$PYTHONPATH}"

LANG_CA="${SPARK_MITM_CA_DIR:-$SPARK_ROOT/out/browser/ca}"
PRODUCT_CA="$BROWSER/data/ca"
STATUS_JSON="$SPARK_ROOT/out/browser/ca.json"

usage() {
  echo "usage: spark-mitm-ca --init|--status|--install [--system]" >&2
  exit 2
}

cmd="${1:-}"
shift || true

case "$cmd" in
  --init)
    mkdir -p "$(dirname "$STATUS_JSON")" "$LANG_CA"
    "$PY" -m spark_browser ca-init --ca-dir "$LANG_CA"
    # Keep product tree in sync when present (MITM-in-Spark lane).
    if [[ -d "$BROWSER/spark_browser" ]]; then
      "$PY" -m spark_browser ca-init --ca-dir "$PRODUCT_CA"
    fi
    cat >"$STATUS_JSON" <<EOF
{
  "op": "ca_init",
  "ok": true,
  "ca_dir": "out/browser/ca",
  "product_ca": "$PRODUCT_CA",
  "system_trust": "never auto",
  "install": "mitm ca-install (--live)",
  "helper": "./spark-mitm-ca --init"
}
EOF
    echo "CA ready: $LANG_CA (+ product $PRODUCT_CA)"
    ;;
  --status)
    ok=0
    if [[ -f "$LANG_CA/ca.pem" && -f "$LANG_CA/ca.key" ]]; then
      echo "language CA: present ($LANG_CA)"
      ok=1
    else
      echo "language CA: missing ($LANG_CA)"
    fi
    if [[ -f "$PRODUCT_CA/ca.pem" && -f "$PRODUCT_CA/ca.key" ]]; then
      echo "product CA: present ($PRODUCT_CA)"
      ok=1
    else
      echo "product CA: missing ($PRODUCT_CA)"
    fi
    if [[ "$ok" -eq 1 ]]; then
      exit 0
    fi
    exit 1
    ;;
  --install)
    # Explicit only — asm refuses without --live.
    INSTALL="$BROWSER/scripts/install-ca.sh"
    if [[ ! -x "$INSTALL" ]]; then
      echo "error: missing $INSTALL" >&2
      exit 1
    fi
    # Prefer product CA; fall back to language CA for NSS install.
    if [[ ! -f "$PRODUCT_CA/ca.pem" && -f "$LANG_CA/ca.pem" ]]; then
      mkdir -p "$PRODUCT_CA"
      cp -a "$LANG_CA/ca.pem" "$PRODUCT_CA/ca.pem"
      [[ -f "$LANG_CA/ca.key" ]] && cp -a "$LANG_CA/ca.key" "$PRODUCT_CA/ca.key"
      [[ -f "$LANG_CA/ca.meta.json" ]] && \
        cp -a "$LANG_CA/ca.meta.json" "$PRODUCT_CA/ca.meta.json"
    fi
    exec "$INSTALL" "${1:-}"
    ;;
  *)
    usage
    ;;
esac
