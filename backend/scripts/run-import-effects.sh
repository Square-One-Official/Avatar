#!/usr/bin/env bash
# E55.5 — wrapper voor import-effects.mjs: haalt de prod-env op, draait eerst
# een dry-run en vraagt om bevestiging vóór de echte run. Draai vanuit de
# repo-root (of geef het pad): bash backend/scripts/run-import-effects.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
ENV_FILE="$(mktemp /tmp/aaavatar-env.XXXXXX)"
trap 'rm -f "$ENV_FILE"' EXIT

cd "$REPO"
vercel env pull "$ENV_FILE" --environment=production --yes

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

if [ -z "${PAYLOAD_API_URL:-}" ] || [ -z "${PAYLOAD_API_KEY:-}" ]; then
  echo "Env onvolledig — PAYLOAD_API_URL/PAYLOAD_API_KEY missen in $ENV_FILE" >&2
  exit 1
fi

echo "Env geladen. PAYLOAD_API_URL=$PAYLOAD_API_URL"
echo
echo "=== dry-run ==="
node "$HERE/import-effects.mjs" "$@"

echo
read -r -p "Doorgaan met de echte run (--apply)? [y/N] " confirm
if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
  node "$HERE/import-effects.mjs" --apply "$@"
  echo
  read -r -p "Oude 4 stijlen (clay,wood,3d,scribble) deactiveren? [y/N] " deact
  if [ "$deact" = "y" ] || [ "$deact" = "Y" ]; then
    node "$HERE/import-effects.mjs" --deactivate clay,wood,3d,scribble --apply
  fi
else
  echo "Echte run overgeslagen."
fi
