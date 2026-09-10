#!/usr/bin/env bash
# deploy-site.sh — atomic full-tree deploy of website/ to Cloudflare Pages.
#
# Project: sparklang-dev (DIRECT UPLOAD — no git integration; see
# docs/CI_PAGES.md). One `wrangler pages deploy` of the whole website/
# tree per run: no rsync filters, no partial syncs, no per-file picks.
# Pages deployments are immutable asset bundles, so the live site flips
# atomically when the upload completes — never a half-synced mix.
#
# Safety defaults (each refusal has an explicit override flag):
#   * refuse a dirty website/ tree            (--allow-dirty)
#   * refuse a HEAD that is not on origin/main (--allow-unmerged)
#
# Usage:
#   tools/deploy-site.sh              deploy HEAD (clean + merged)
#   tools/deploy-site.sh --dry-run    print what would ship, exit 0
#
# Auth: wrangler OAuth on the deploy host (see docs/CI_PAGES.md).
# Never print tokens.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

PROJECT="sparklang-dev"
BRANCH="production"
ALLOW_DIRTY=0
ALLOW_UNMERGED=0
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --allow-dirty) ALLOW_DIRTY=1 ;;
    --allow-unmerged) ALLOW_UNMERGED=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      echo "unknown arg: $arg" >&2
      exit 2
      ;;
  esac
done

SHA="$(git rev-parse HEAD)"
DIRTY=0
if [ -n "$(git status --porcelain -- website/)" ]; then
  DIRTY=1
fi

if [ "$DIRTY" -eq 1 ] && [ "$ALLOW_DIRTY" -eq 0 ]; then
  echo "refusing: uncommitted changes under website/:" >&2
  git status --porcelain -- website/ >&2
  echo "(commit first, or --allow-dirty to override)" >&2
  exit 1
fi

if [ "$ALLOW_UNMERGED" -eq 0 ]; then
  git fetch --quiet origin main
  if ! git merge-base --is-ancestor HEAD origin/main; then
    echo "refusing: HEAD $SHA is not on origin/main" >&2
    echo "(merge first, or --allow-unmerged to override)" >&2
    exit 1
  fi
fi

echo "deploy: website/ @ $SHA -> Pages $PROJECT (branch $BRANCH)"
echo "mode:   full-tree atomic upload (no filters, no partial sync)"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "dry run — no upload"
  exit 0
fi

DIRTY_FLAG="false"
if [ "$DIRTY" -eq 1 ]; then
  DIRTY_FLAG="true"
fi

npx wrangler pages deploy website \
  --project-name="$PROJECT" \
  --branch="$BRANCH" \
  --commit-hash="$SHA" \
  --commit-dirty="$DIRTY_FLAG"
