#!/usr/bin/env bash
# Shadow-copy: mirror sources into out/shadow/<name>/ for isolated builds.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NAME="${1:-default}"
DEST="${SPARK_SHADOW_ROOT:-$ROOT/out/shadow}/$NAME"
mkdir -p "$DEST"
# Core compile/decompile surface
rsync -a --delete \
  --exclude '.git' --exclude 'out/' --exclude '__pycache__' \
  --exclude '.wrangler' --exclude 'website/.wrangler' \
  "$ROOT/bootstrap" "$ROOT/python" "$ROOT/selfhost" \
  "$ROOT/examples" "$ROOT/docs" "$ROOT/tools" \
  "$ROOT/scripts" "$ROOT/asm" "$ROOT/Makefile" \
  "$ROOT/spark.toml" "$DEST/" 2>/dev/null || {
  # Fallback without rsync
  mkdir -p "$DEST"
  for d in bootstrap python selfhost examples docs tools scripts asm; do
    [[ -d "$ROOT/$d" ]] || continue
    rm -rf "$DEST/$d"
    cp -a "$ROOT/$d" "$DEST/$d"
  done
  cp -a "$ROOT/Makefile" "$ROOT/spark.toml" "$DEST/" 2>/dev/null || true
}
# Record provenance
{
  echo "shadow_name=$NAME"
  echo "source_root=$ROOT"
  echo "created_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if command -v git >/dev/null 2>&1; then
    echo "git_head=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || true)"
  fi
} >"$DEST/SHADOW_META.txt"
echo "shadow-copy → $DEST"
