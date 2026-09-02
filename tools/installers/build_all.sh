#!/usr/bin/env bash
# Orchestrate Spark runtime installer builds (all CPU arches).
set -euo pipefail

INSTALLERS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$INSTALLERS/../.." && pwd)"

VERSION="${1:?usage: build_all.sh VERSION [STAGE_DIR] [OUT_DIR]}"
STAGE_DIR="${2:-$ROOT/out/runtime-pack}"
OUT_DIR="${3:-$ROOT/website/downloads}"
DOWNLOAD_BASE="${SPARK_DOWNLOAD_BASE:-https://sparklang.dev/downloads}"

exec "$ROOT/tools/package_runtime.sh"
