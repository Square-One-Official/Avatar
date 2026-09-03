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

# E55-ship-les: PAYLOAD_API_KEY is in Vercel als Sensitive gemarkeerd en komt
# uit `vercel env pull` als LEGE string terug. Volgorde daarom: (1) al gezet in
# de omgeving → gebruiken; (2) anders pull proberen; (3) leeg → duidelijke
# instructie waar de key te halen is.
export PAYLOAD_API_URL="${PAYLOAD_API_URL:-https://admin.aaavatar.nl}"
if [ -z "${PAYLOAD_API_KEY:-}" ]; then
  vercel env pull "$ENV_FILE" --environment=production --yes
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

if [ -z "${PAYLOAD_API_KEY:-}" ]; then
  cat >&2 <<'MSG'
PAYLOAD_API_KEY ontbreekt (Vercel markeert 'm Sensitive — pull levert leeg).
Haal de key uit de Payload-admin (admin.aaavatar.nl → Users → jouw user →
"API Key" tonen) of uit 1Password, en draai:

  PAYLOAD_API_KEY=… bash backend/scripts/run-import-effects.sh
MSG
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
