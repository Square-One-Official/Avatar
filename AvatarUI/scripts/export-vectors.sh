#!/bin/zsh
# DS-vectorexport voor Figma-sync: rendert de catalogus (DSVectorCatalogExportTests)
# naar PDF, zet om naar SVG (PyMuPDF) en normaliseert
# de eenheden (pt → px, 1 SwiftUI-punt = 1 Figma-px).
#
#   AvatarUI/scripts/export-vectors.sh [uitvoermap]   (default: build/ds-vectors)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-$PWD/build/ds-vectors}"
mkdir -p "$OUT"
setopt null_glob
rm -f "$OUT"/*.pdf "$OUT"/*.svg
python3 -c "import fitz" 2>/dev/null || { echo "PyMuPDF ontbreekt: pip3 install pymupdf" >&2; exit 1; }

LOG="$(mktemp)"
if ! DS_VECTOR_DUMP_DIR="$OUT" swift test --filter DSVectorCatalogExportTests >"$LOG" 2>&1; then
  grep -E "error:|failed" "$LOG" >&2 || tail -20 "$LOG" >&2
  exit 1
fi
grep -E "DS_VECTOR_DUMP" "$LOG" || true
python3 "$(dirname "$0")/pdf-to-svg.py" "$OUT"
