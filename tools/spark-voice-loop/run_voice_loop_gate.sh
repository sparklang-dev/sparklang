#!/usr/bin/env bash
# Offline gate for voice-loop language companions.
set -euo pipefail
cd "$(dirname "$0")/../.."

install -m 755 tools/spark-voice-loop/spark_voice_loop.sh spark-voice-loop
install -m 755 tools/spark-serve-ref/spark_serve_ref.sh spark-serve-ref

mkdir -p out/pref-001
printf 'spark-pref dry\n' > out/pref-001/ARTIFACT

run_grep() {
  local prog="$1"
  local pat="$2"
  local out="/tmp/spark-vl-gate-$$.txt"
  ./spark --dry-run "$prog" >"$out"
  grep -qE "$pat" "$out"
}

run_grep examples/pairs_basic.spark '"op": ?"pairs"'
run_grep examples/expect_score.spark '"op": ?"expect_score"'
run_grep examples/serve_helper.spark '"op": ?"serve_helper"'
./spark-serve-ref --dry \
  --helper examples/fixtures/voice_loop/agents/agent-a \
  --as ranker --mode shadow --port 8091 \
  >/tmp/spark-vl-serve-ref.json
grep -qE '"op": ?"serve_helper"' /tmp/spark-vl-serve-ref.json
run_grep examples/ground_fact.spark '"op": ?"ground"'
run_grep examples/bench_agents.spark '"op": ?"bench"'
run_grep examples/schedule_nightly.spark '"op": ?"schedule"'
test -f out/voice_loop/nightly-summary.json

PYTHONPATH=python python3 tools/spark-voice-loop/test_voice_loop.py

echo "test-voice-loop OK"
