#!/usr/bin/env bash
# Public AI-gateway probe for Spark ask — probe credential only.
# Never echo/log/write the probe credential. On 401 → credential unavailable; stop.
# Does not ask to mint PAT. Does not reuse cursor-ide.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

BIFROST_URL="${BIFROST_URL:?set BIFROST_URL to your public AI gateway}"
export BIFROST_URL
PID_FILE="${INFISICAL_BIFROST_PROBES_PROJECT_ID_FILE:-${SPARK_ASK_PROBE_SECRETS_DIR:-$HOME/.config/spark/secrets}/gateway-probes-project-id.txt}"
MI_FILE="${INFISICAL_BIFROST_PROBE_MI:-${SPARK_ASK_PROBE_SECRETS_DIR:-$HOME/.config/spark/secrets}/gateway-probe-machine-identity.env}"
DOMAIN="${INFISICAL_API_URL:-http://127.0.0.1:8222/api}"

PROJECT_ID="${INFISICAL_BIFROST_PROBES_PROJECT_ID:-}"
if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "<PROJECT_ID>" ]]; then
  if [[ -f "$PID_FILE" ]]; then
    PROJECT_ID="$(tr -d '[:space:]' <"$PID_FILE")"
  fi
fi
if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "<PROJECT_ID>" ]]; then
  echo "spark-ask public probe: credential unavailable (no PROJECT_ID)"
  exit 4
fi
if ! command -v infisical >/dev/null 2>&1; then
  echo "spark-ask public probe: credential unavailable (no infisical)"
  exit 4
fi

# Prefer machine-identity UA token when no INFISICAL_TOKEN.
if [[ -z "${INFISICAL_TOKEN:-}" && -f "$MI_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a
  # shellcheck source=/dev/null
  source "$MI_FILE"
  set +a
  INFISICAL_TOKEN="$(
    curl -sS -X POST "${DOMAIN%/api}/api/v1/auth/universal-auth/login" \
      -H 'Content-Type: application/json' \
      -d "{\"clientId\":\"$INFISICAL_UNIVERSAL_AUTH_CLIENT_ID\",\"clientSecret\":\"$INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET\"}" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["accessToken"])'
  )" || true
  export INFISICAL_TOKEN
fi
if [[ -z "${INFISICAL_TOKEN:-}" ]]; then
  echo "spark-ask public probe: credential unavailable (no INFISICAL_TOKEN)"
  exit 4
fi

# Do not print the key. Capture HTTP code only. Model=fast (proven public).
set +e
out="$(
  infisical run --domain "$DOMAIN" --token "$INFISICAL_TOKEN" \
    --projectId "$PROJECT_ID" --env prod --path /bifrost/probes --silent -- \
    bash -c 'curl -sS -o /tmp/spark-ask-public-body.json -w "%{http_code}" \
      "$BIFROST_URL/v1/chat/completions" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $VK_PROBE" \
      -d "{\"model\":\"fast\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"max_tokens\":8}"'
)"
rc=$?
set -e

if [[ "$rc" -ne 0 ]]; then
  echo "spark-ask public probe: credential unavailable (infisical/curl rc=$rc)"
  exit 4
fi
if [[ "$out" == "401" ]]; then
  echo "spark-ask public probe: credential unavailable"
  exit 4
fi
if [[ "$out" != "200" ]]; then
  echo "spark-ask public probe: HTTP $out (no routing conclusion invented)"
  exit 1
fi
echo "spark-ask public probe: HTTP 200 (body not printed)"
exit 0
