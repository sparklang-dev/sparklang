#!/usr/bin/env bash
# Run AFTER Michael creates org sparklang-dev (or rename) and you can:
#   gh api user/memberships/orgs/sparklang-dev
set -euo pipefail
ORG="${1:-sparklang-dev}"
REPO="${2:-sparklang}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
gh api "user/memberships/orgs/${ORG}" --jq '{state:.state,role:.role}' >/dev/null
if ! gh repo view "${ORG}/${REPO}" >/dev/null 2>&1; then
  gh repo create "${ORG}/${REPO}" --public \
    --description "SparkLang — AI programming language" \
    --homepage "https://sparklang.dev" \
    --source "$ROOT" --remote origin --push
else
  git remote remove origin 2>/dev/null || true
  git remote add origin "https://github.com/${ORG}/${REPO}.git"
  git push -u origin main
fi
gh repo edit "${ORG}/${REPO}" \
  --homepage "https://sparklang.dev" \
  --description "SparkLang — AI programming language" \
  --add-topic sparklang --add-topic dsl --add-topic llm \
  --add-topic programming-language --add-topic ai || true
echo "Public: https://github.com/${ORG}/${REPO}"
