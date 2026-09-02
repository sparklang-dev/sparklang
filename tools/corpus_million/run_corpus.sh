#!/usr/bin/env bash
# Launch / resume corpus toward 1M real examples.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
mkdir -p data
exec python3 tools/corpus_million/run_corpus.py "$@"
