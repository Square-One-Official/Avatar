#!/bin/bash
# E53.9 — icoongrootte-guard.
#
# Alle icoon-maten in Features lopen via DSIconSize (de sweep van 2026-08-01
# zette 70 losse puntgetallen om). Eén nieuw literal glipt er zo weer in en
# daarmee begint de schaduwschaal opnieuw — deze grep houdt 'm op nul.
# Banner-canvas-TEKST (user content) rendert via NSFont en matcht dit patroon
# dus niet; er zijn geen legitieme uitzonderingen.
set -euo pipefail
cd "$(dirname "$0")/.."

violations=$(
  grep -rn --include='*.swift' -E '\.font\(\.system\(size: [0-9]' Avatar2/Features || true
)

if [ -n "$violations" ]; then
  echo "❌ Losse icoon-/tekstpuntgetallen gevonden (E53.9) — gebruik DSIconSize of een DS-tekststijl:"
  echo "$violations"
  exit 1
fi
echo "✅ geen losse puntgetallen — icoon-maten lopen via DSIconSize"
