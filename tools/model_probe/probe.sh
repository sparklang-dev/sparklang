#!/usr/bin/env bash
# Optional model endpoint probe — NOT linked into ./spark, NOT in make test.
# Read-only discovery + catalog append. Never kills voice/:8010.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
mkdir -p data
CATALOG=data/model-catalog.jsonl
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "[model-probe] read-only; SPARK_ALLOW_NET=${SPARK_ALLOW_NET:-0}"

# Configured aliases from spark.toml (documented defaults)
for id in fast code best; do
  echo "{\"ts\":\"$TS\",\"id\":\"$id\",\"kind\":\"alias\",\"probe\":\"config-listed\",\"source\":\"spark.toml\"}" \
    >> "$CATALOG"
done

# Local listen discovery (ss) — list only; never kill
if command -v ss >/dev/null 2>&1; then
  while read -r port; do
    case "$port" in
      8010)
        echo "{\"ts\":\"$TS\",\"id\":\"local:vllm@:8010\",\"kind\":\"local_vllm\",\"probe\":\"listed-readonly\",\"skipped_reason\":\"voice-only — never Spark compute / never kill\"}" \
          >> "$CATALOG"
        ;;
      8003|8000|8080)
        echo "{\"ts\":\"$TS\",\"id\":\"local:vllm@:$port\",\"kind\":\"local_vllm\",\"probe\":\"listening\",\"endpoint\":\"127.0.0.1:$port\"}" \
          >> "$CATALOG"
        ;;
    esac
  done < <(ss -ltn 2>/dev/null | awk 'NR>1 {print $4}' | sed -n 's/.*:\([0-9]*\)$/\1/p' | sort -u)
fi

# Public AI gateway — only if SPARK_ALLOW_NET=1 and probe secrets available
if [[ "${SPARK_ALLOW_NET:-0}" == "1" ]]; then
  if command -v infisical >/dev/null 2>&1; then
    echo "[model-probe] Public gateway probe requires gateway probe credential"
    echo "[model-probe] On HTTP 401: credential unavailable — no routing conclusion"
    # Do not echo secrets. Placeholder: caller wraps with infisical run.
    echo "{\"ts\":\"$TS\",\"id\":\"public-ai-gateway.example\",\"kind\":\"public_bifrost\",\"probe\":\"attempt-gated\",\"note\":\"wrap with probe credential; 401=credential unavailable\"}" \
      >> "$CATALOG"
  else
    echo "{\"ts\":\"$TS\",\"id\":\"public-ai-gateway.example\",\"kind\":\"public_bifrost\",\"probe\":\"skipped\",\"skipped_reason\":\"credential unavailable (no probe credential)\"}" \
      >> "$CATALOG"
  fi
else
  echo "{\"ts\":\"$TS\",\"id\":\"public-ai-gateway.example\",\"kind\":\"public_bifrost\",\"probe\":\"skipped\",\"skipped_reason\":\"SPARK_ALLOW_NET!=1 — dry/local only\"}" \
    >> "$CATALOG"
fi

echo "[model-probe] appended rows → $CATALOG"
echo "[model-probe] done (no train@, no host reboot, no live voice inject)"
