#!/usr/bin/env bash
#
# release-v2.sh — Build, sign, notarize en publiceer een Aaavatar 2-release
# (E13.1). Eigen kanaal naast scripts/release.sh (v1): eigen appcast
# (appcast-v2.xml) en eigen tag-reeks (v2.x.y).
#
# Download-link: de website linkt naar
#   …/Avatar/releases/latest/download/Aaavatar.dmg
# en GitHub's "latest" is de nieuwste NIET-prerelease. Sinds 2.0 de
# publieke release is (besluit Thierry 2026-09-04) publiceert dit script
# daarom (a) een stabiele kopie onder exact die naam, `Aaavatar.dmg`, en
# (b) standaard als gewone release met `--latest`. Wil je een build eerst
# staged hebben (Sparkle-e2e vóór de site 'm serveert): PRERELEASE=1 —
# daarna `gh release edit v<ver> --prerelease=false --latest` om live te gaan.
#
# Usage:
#   ./scripts/release-v2.sh 2.0.0 101
#   PRERELEASE=1 ./scripts/release-v2.sh 2.0.0 101      # staged
#   (MARKETING_VERSION=2.0.0, CURRENT_PROJECT_VERSION=101 — buildnummers voor
#    dit kanaal starten op 100, zie project.yml.)
#
# Release-notes: het script leest docs/releases/RELEASE-NOTES-<ver>.md
# (verplicht, gecommit). `--generate-notes` zou v1.2.1..v2.0.0 = honderden
# commits opsommen.
#
# Vereisten: identiek aan release.sh (create-dmg, gh, notarytool-profiel
# "AC_PASSWORD", Sparkle sign_update met dezelfde private key als v1 — de
# targets delen de SUPublicEDKey).
#
set -euo pipefail

VERSION="${1:?Usage: release-v2.sh <version> <build>  (bv. release-v2.sh 2.0.0 101)}"
BUILD="${2:?Usage: release-v2.sh <version> <build>  (bv. release-v2.sh 2.0.0 101)}"
PRERELEASE="${PRERELEASE:-0}"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
NOTES_FILE="$PROJECT_DIR/docs/releases/RELEASE-NOTES-${VERSION}.md"
if [[ ! -s "$NOTES_FILE" ]]; then
  echo "❌ Release-notes ontbreken: $NOTES_FILE (schrijf ze vóór je archiveert)."
  exit 1
fi
ARCHIVE_PATH="$BUILD_DIR/Avatar2.xcarchive"
EXPORT_DIR="$BUILD_DIR/export-v2"
DMG_NAME="Aaavatar-2-${VERSION}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
SCHEME="Avatar2"
APP_NAME="Aaavatar 2.app"
# Tag-reeks: gewoon v<versie> — v1 is bevroren op 1.x, dus v2.x.y kan nooit
# botsen, en een tag zónder slash houdt de download-URL's encoding-vrij.
TAG="v${VERSION}"

# Zelfde gepinde sign_update als release.sh (Keychain-ACL aan vast pad).
SIGN_UPDATE_CACHE_DIR="$HOME/Library/Caches/avatar-release"
SIGN_UPDATE="$SIGN_UPDATE_CACHE_DIR/sign_update"
if [[ ! -x "$SIGN_UPDATE" || -n "${SIGN_UPDATE_PATH:-}" ]]; then
  SIGN_UPDATE_SRC="${SIGN_UPDATE_PATH:-$(find ~/Library/Developer/Xcode/DerivedData -path '*/artifacts/sparkle/Sparkle/bin/sign_update' -type f 2>/dev/null | head -1)}"
  if [[ -z "$SIGN_UPDATE_SRC" ]]; then
    echo "❌ sign_update niet gevonden — bouw eerst een keer, of zet SIGN_UPDATE_PATH."
    exit 1
  fi
  echo "→ sign_update pinnen naar $SIGN_UPDATE..."
  mkdir -p "$SIGN_UPDATE_CACHE_DIR"
  cp "$SIGN_UPDATE_SRC" "$SIGN_UPDATE"
  chmod +x "$SIGN_UPDATE"
fi

echo "📦 Releasing Aaavatar 2 v${VERSION} (build ${BUILD})"

# 1. Versie-bump: alléén de Avatar2-target-overrides (E13.1) — de root-settings
#    zijn van v1 en blijven staan. We herkennen het v2-blok aan de tweede
#    MARKETING_VERSION-match in het bestand.
echo "→ Versie bumpen in project.yml (Avatar2-blok)..."
cd "$PROJECT_DIR"
RELEASE_VERSION="$VERSION" RELEASE_BUILD="$BUILD" python3 - <<'PYEOF'
import os, re, pathlib
p = pathlib.Path("project.yml")
s = p.read_text()

def bump_second(pattern, replacement, s):
    hits = [m for m in re.finditer(pattern, s)]
    assert len(hits) == 2, f"verwachtte precies 2× {pattern!r} (root=v1, target=v2), vond {len(hits)}"
    m = hits[1]
    return s[:m.start()] + replacement + s[m.end():]

s = bump_second(r'MARKETING_VERSION: "[^"]*"',
                f'MARKETING_VERSION: "{os.environ["RELEASE_VERSION"]}"', s)
s = bump_second(r'CURRENT_PROJECT_VERSION: "[^"]*"',
                f'CURRENT_PROJECT_VERSION: "{os.environ["RELEASE_BUILD"]}"', s)
p.write_text(s)
PYEOF

# 2. Xcode-project regenereren
echo "→ xcodegen generate..."
xcodegen generate

# 3. Archiveren
echo "→ Archiving..."
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"
xcodebuild \
  -project Avatar.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  archive

# 4. Exporteren (Developer ID)
echo "→ Exporting..."
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions-v2.plist"
cat > "$EXPORT_OPTIONS" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
</dict>
</plist>
PLIST

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

# 5. DMG (zelfde stijl-assets als v1)
echo "→ Building DMG..."
if ! command -v create-dmg >/dev/null 2>&1; then
  echo "❌ create-dmg niet gevonden. Installeer met: brew install create-dmg"
  exit 1
fi

DMG_BACKGROUND="$PROJECT_DIR/scripts/dmg-assets/background.tiff"
if [[ ! -f "$DMG_BACKGROUND" ]]; then
  echo "→ DMG-achtergrond renderen..."
  python3 "$PROJECT_DIR/scripts/dmg-assets/build-background.py"
fi

rm -f "$DMG_PATH"
create-dmg \
  --volname "Aaavatar 2" \
  --background "$DMG_BACKGROUND" \
  --window-size 660 420 \
  --icon-size 128 \
  --icon "$APP_NAME" 165 215 \
  --app-drop-link 495 215 \
  --hide-extension "$APP_NAME" \
  --no-internet-enable \
  "$DMG_PATH" \
  "$EXPORT_DIR/$APP_NAME"

# 6. Notariseren
echo "→ Notarizing..."
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "AC_PASSWORD" \
  --wait

# 7. Staple
echo "→ Stapling..."
xcrun stapler staple "$DMG_PATH"

# 8. EdDSA-handtekening
echo "→ Signing with EdDSA..."
SIGNATURE_OUTPUT=$("$SIGN_UPDATE" "$DMG_PATH")
echo "   $SIGNATURE_OUTPUT"
ED_SIGNATURE=$(echo "$SIGNATURE_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
LENGTH=$(stat -f%z "$DMG_PATH")

# 9. appcast-v2 bijwerken (nieuwste item bovenaan)
echo "→ Updating appcast-v2..."
PUBDATE=$(date -R)
APPCAST_PATH="$PROJECT_DIR/appcast-v2.xml" \
APPCAST_VERSION="$VERSION" \
APPCAST_BUILD="$BUILD" \
APPCAST_PUBDATE="$PUBDATE" \
APPCAST_LENGTH="$LENGTH" \
APPCAST_DMG_NAME="$DMG_NAME" \
APPCAST_TAG="$TAG" \
APPCAST_ED_SIGNATURE="$ED_SIGNATURE" \
python3 - <<'PYEOF'
import os
path = os.environ["APPCAST_PATH"]
tag = os.environ["APPCAST_TAG"]
item = (
    "    <item>\n"
    f"      <title>Version {os.environ['APPCAST_VERSION']}</title>\n"
    f"      <pubDate>{os.environ['APPCAST_PUBDATE']}</pubDate>\n"
    f"      <sparkle:version>{os.environ['APPCAST_BUILD']}</sparkle:version>\n"
    f"      <sparkle:shortVersionString>{os.environ['APPCAST_VERSION']}</sparkle:shortVersionString>\n"
    "      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>\n"
    "      <enclosure\n"
    f"        url=\"https://github.com/Square-One-Official/Avatar/releases/download/{tag}/{os.environ['APPCAST_DMG_NAME']}\"\n"
    f"        length=\"{os.environ['APPCAST_LENGTH']}\"\n"
    "        type=\"application/x-apple-diskimage\"\n"
    f"        sparkle:edSignature=\"{os.environ['APPCAST_ED_SIGNATURE']}\" />\n"
    "    </item>\n"
)
with open(path) as f:
    text = f.read()
needle = "<channel>"
i = text.index(needle) + len(needle)
if text[i:i+1] == "\n":
    i += 1
text = text[:i] + item + text[i:]
with open(path, "w") as f:
    f.write(text)
PYEOF

# Spiegel naar de backend-deploy (api.aaavatar.nl/appcast-v2.xml).
cp "$PROJECT_DIR/appcast-v2.xml" "$PROJECT_DIR/backend/api/_appcast-v2.xml"

# 10. GitHub-release. Stabiele kopie heet exact `Aaavatar.dmg` — dat is wat
#     releases/latest/download/Aaavatar.dmg (website) oplost. Idempotent bij
#     herhaalde runs (assets overschrijven, vlag niet aanraken).
STABLE_DMG_PATH="$BUILD_DIR/Aaavatar.dmg"
cp "$DMG_PATH" "$STABLE_DMG_PATH"

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "→ release $TAG bestaat al — DMG-assets overschrijven"
  gh release upload "$TAG" "$DMG_PATH" "$STABLE_DMG_PATH" --clobber
elif [[ "$PRERELEASE" == "1" ]]; then
  echo "→ Creating GitHub prerelease (staged; site blijft op de vorige 'latest')..."
  gh release create "$TAG" "$DMG_PATH" "$STABLE_DMG_PATH" \
    --title "Aaavatar 2 v${VERSION}" \
    --prerelease \
    --notes-file "$NOTES_FILE"
else
  echo "→ Creating GitHub release (latest)..."
  gh release create "$TAG" "$DMG_PATH" "$STABLE_DMG_PATH" \
    --title "Aaavatar 2 v${VERSION}" \
    --latest \
    --notes-file "$NOTES_FILE"
fi

echo ""
if [[ "$PRERELEASE" == "1" ]]; then
  echo "✅ Aaavatar 2 v${VERSION} gepubliceerd als PRERELEASE (staged)."
else
  echo "✅ Aaavatar 2 v${VERSION} gepubliceerd (latest)."
fi
echo ""
echo "Niet vergeten:"
echo "  1. appcast-v2.xml + backend/api/_appcast-v2.xml verifiëren en committen"
echo "  2. Backend deployen (main pushen) zodat api.aaavatar.nl/appcast-v2.xml het nieuwe item serveert"
echo "  3. Smoke: curl -s https://api.aaavatar.nl/appcast-v2.xml | grep ${VERSION}"
if [[ "$PRERELEASE" == "1" ]]; then
  echo "  4. Live: gh release edit ${TAG} --prerelease=false --latest"
fi
