#!/bin/bash
# E53.4 — reduce-motion-guard.
#
# "Verminder beweging" (System Settings → Accessibility) is verplicht, geen
# opt-in per call site. Elke animatie hoort daarom via DSMotion te lopen:
#   - imperatief:  DSMotion.animate(DSMotion.<token>) { … }
#   - declaratief: .dsMotion(DSMotion.<token>, value: …)
#   - transitions: .dsSlide(…, reduceMotion:) / .dsScaleFade(…, reduceMotion:)
#
# Een kale `withAnimation(…)` of `.animation(…)` omzeilt die check stilletjes —
# de code compileert, ziet er goed uit, en negeert de systeeminstelling. Deze
# guard vangt dat vóór de review.
#
# Uitzondering: `DSMotion.animateCrossFade` voor animaties die alléén opacity
# veranderen. Een fade verplaatst niets en mag dus blijven lopen; dat is
# expliciet gemarkeerd i.p.v. een ongemarkeerde kale withAnimation.
set -euo pipefail

cd "$(dirname "$0")/.."

# DSMotion.swift zelf definieert de helpers (en de reduce-motion-fallbacks van
# de transitions), dus dat bestand is per definitie uitgezonderd.
SEARCH_PATHS=(Avatar2 AvatarUI/Sources)
EXCLUDE='AvatarUI/Sources/AvatarUI/Tokens/DSMotion.swift'

violations=$(
  grep -rn --include='*.swift' -E '(^|[^.[:alnum:]])withAnimation\(|\.animation\(' "${SEARCH_PATHS[@]}" \
    | grep -v "^${EXCLUDE}:" \
    | grep -v 'DSMotion\.animate' \
    | grep -v '\.dsMotion(' \
    | grep -v -E '^[^:]+:[0-9]+:[[:space:]]*(//|///|\*)' \
    || true
)

if [ -n "$violations" ]; then
  echo "❌ Kale animaties gevonden — deze omzeilen 'Verminder beweging' (E53.4):"
  echo "$violations"
  echo
  echo "Gebruik DSMotion.animate / .dsMotion / .dsSlide / .dsScaleFade."
  echo "Alleen-opacity? Dan DSMotion.animateCrossFade, met een comment waarom."
  exit 1
fi

echo "✅ geen kale animaties — alle beweging loopt via DSMotion"
