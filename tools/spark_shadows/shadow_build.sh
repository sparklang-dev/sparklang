#!/usr/bin/env bash
# Shadow-build: compile bootstrap + sample .spark inside a shadow tree.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NAME="${1:-default}"
DEST="${SPARK_SHADOW_ROOT:-$ROOT/out/shadow}/$NAME"
if [[ ! -d "$DEST" ]]; then
  bash "$(dirname "$0")/shadow_copy.sh" "$NAME"
fi
cd "$DEST"
make spark-bootstrap
SAMPLE="${2:-selfhost/compile.spark}"
if [[ ! -f "$SAMPLE" ]]; then
  SAMPLE="examples/spark_builder.spark"
fi
mkdir -p out/shadow-build
./spark-bootstrap --compile "$SAMPLE" -o out/shadow-build/sample.sparkbc
sha256sum out/shadow-build/sample.sparkbc | tee out/shadow-build/sample.sha256
echo "shadow-build OK ($DEST)"
