#!/bin/zsh
# Scherm-vectorexport voor Figma-sync: draait Avatar2Tests/ScreenVectorExportTests
# (echte ShellView + gezaaide store) en zet de PDF's om naar SVG.
#
#   AvatarUI/scripts/export-screens.sh [uitvoermap] [derivedDataPath]
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:-$PWD/build/screen-vectors}"
DERIVED="${2:-build/dd}"
mkdir -p "$OUT"; setopt null_glob; rm -f "$OUT"/*.pdf "$OUT"/*.svg
LOG="$(mktemp)"
# De test-host kan ná de test nog crashen (async model-taken op een gereset
# context); de dump telt, niet de exit-code.
TEST_RUNNER_SCREEN_VECTOR_DUMP_DIR=TMP xcodebuild -project Avatar.xcodeproj -scheme Avatar2 \
    -configuration Debug -derivedDataPath "$DERIVED" test \
    -only-testing:Avatar2Tests/ScreenVectorExportTests >"$LOG" 2>&1 || true
if ! grep -q "SCREEN_VECTOR_DUMP:" "$LOG"; then
  grep -E "error:|failed|Fatal" "$LOG" >&2 | head -20 || tail -30 "$LOG" >&2
  exit 1
fi
SRC="$(grep -o 'SCREEN_VECTOR_DUMP: .* bestanden in .*' "$LOG" | sed 's/.* bestanden in //' | tail -1)"
[[ -d "$SRC" ]] || { echo "geen dump-map gevonden in log ($LOG)" >&2; exit 1; }
cp "$SRC"/*.pdf "$OUT"/
python3 "$(dirname "$0")/pdf-to-svg.py" "$OUT"
