#!/usr/bin/env bash
#
# prod-gtm-smoke.sh — unauthenticated production smokes for the GTM-cut
# go-live. Does NOT create Stripe Checkout sessions or spend credits.
#
# Usage: ./scripts/prod-gtm-smoke.sh
# Env:   API_BASE (default https://api.aaavatar.nl)
#
set -euo pipefail

API="${API_BASE:-https://api.aaavatar.nl}"
FAIL=0

check() {
  local name="$1" expect="$2"
  shift 2
  local tmp
  tmp="$(mktemp)"
  local code
  code="$(curl -sS -o "$tmp" -w '%{http_code}' "$@")"
  local body
  body="$(cat "$tmp")"
  rm -f "$tmp"
  if [[ "$code" != "$expect" ]]; then
    echo "FAIL  $name  HTTP $code (expected $expect)  $body"
    FAIL=1
    return
  fi
  echo "OK    $name  HTTP $code  ${body:0:120}"
}

echo "→ GTM production smoke against $API"
echo

check "appcast-v2" 200 "$API/appcast-v2.xml"
if ! curl -sS "$API/appcast-v2.xml" | grep -q '<channel>'; then
  echo "FAIL  appcast-v2 body missing <channel>"
  FAIL=1
fi

check "appcast-v1" 200 "$API/appcast.xml"
if ! curl -sS "$API/appcast.xml" | grep -q 'sparkle:shortVersionString'; then
  echo "FAIL  appcast-v1 missing version"
  FAIL=1
fi

check "effects" 200 "$API/v1/effects"
python3 - "$API" <<'PY' || FAIL=1
import json, sys, urllib.request
api = sys.argv[1]
with urllib.request.urlopen(api + "/v1/effects") as r:
    d = json.load(r)
effects = d.get("effects") or []
keys = [e.get("key") for e in effects]
print(f"OK    effects count={len(effects)} keys={keys}")
if len(effects) < 1:
    print("FAIL  expected at least one live effect", file=sys.stderr)
    sys.exit(1)
old = {"clay", "wood", "3d", "scribble"}
live_old = old.intersection(keys)
if live_old:
    print(f"FAIL  retired styles still live: {sorted(live_old)}", file=sys.stderr)
    sys.exit(1)
PY

check "feature-flags" 200 "$API/v1/feature-flags"

check "stylize unauth" 401 -X POST "$API/v1/stylize" -H 'content-type: application/json' -d '{}'
check "subscribe unauth" 401 -X POST "$API/v1/checkout/subscribe" -H 'content-type: application/json' -d '{}'
check "topup unauth" 401 -X POST "$API/v1/checkout/topup" -H 'content-type: application/json' -d '{}'
check "portal unauth" 401 -X POST "$API/v1/portal" -H 'content-type: application/json' -d '{}'
check "colorize unauth" 401 -X POST "$API/v1/colorize" -H 'content-type: application/json' -d '{}'
check "fill-body unauth" 401 -X POST "$API/v1/fill-body" -H 'content-type: application/json' -d '{}'
check "upscale unauth" 401 -X POST "$API/v1/upscale" -H 'content-type: application/json' -d '{}'

check "subscribe-anonymous no fingerprint" 400 \
  -X POST "$API/v1/checkout/subscribe-anonymous" -H 'content-type: application/json' -d '{}'

check "import-claim no fingerprint" 400 \
  -X POST "$API/v1/import-claim" -H 'content-type: application/json' -d '{}'

check "recovery invalid email" 400 \
  -X POST "$API/v1/auth/send-recovery-email" -H 'content-type: application/json' \
  -d '{"email":"not-an-email"}'

check "recovery unknown email (anti-enum)" 200 \
  -X POST "$API/v1/auth/send-recovery-email" -H 'content-type: application/json' \
  -d '{"email":"nobody-gtm-smoke@example.com"}'

check "account anonymous free quota" 200 "$API/v1/account"

check "website" 200 "https://aaavatar.nl/"

# v1 latest DMG must keep resolving after any 2.0 prerelease.
dmg_code="$(curl -sS -o /dev/null -w '%{http_code}' -I \
  https://github.com/Square-One-Official/Avatar/releases/latest/download/Aaavatar.dmg)"
# GitHub may 302 to the asset.
if [[ "$dmg_code" != "302" && "$dmg_code" != "200" ]]; then
  echo "FAIL  v1 latest DMG HTTP $dmg_code"
  FAIL=1
else
  loc="$(curl -sS -I https://github.com/Square-One-Official/Avatar/releases/latest/download/Aaavatar.dmg \
    | tr -d '\r' | awk 'tolower($1)=="location:"{print $2; exit}')"
  echo "OK    v1 latest DMG HTTP $dmg_code  $loc"
  if [[ -n "$loc" && "$loc" == *Aaavatar-2* ]]; then
    echo "FAIL  latest DMG was stolen by a 2.0 release: $loc"
    FAIL=1
  fi
fi

echo
if [[ "$FAIL" -ne 0 ]]; then
  echo "❌ GTM production smoke FAILED"
  exit 1
fi
echo "✅ GTM production smoke groen"
