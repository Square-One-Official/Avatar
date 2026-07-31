#!/usr/bin/env bash
#
# release.sh — Build, sign, notarize, and publish an Avatar release.
#
# Usage:
#   ./scripts/release.sh 1.1 2
#   (MARKETING_VERSION=1.1, CURRENT_PROJECT_VERSION=2)
#
# Requirements:
#   - Xcode command-line tools
#   - xcodegen (brew install xcodegen)
#   - create-dmg (brew install create-dmg)
#   - gh CLI (brew install gh), authenticated
#   - Sparkle's sign_update tool (see step 0)
#   - Apple Developer ID certificate in Keychain
#   - App-specific password for notarytool: stored as Keychain profile "AC_PASSWORD"
#     (xcrun notarytool store-credentials "AC_PASSWORD" ...)
#
set -euo pipefail

VERSION="${1:?Usage: release.sh <version> <build>  (e.g. release.sh 1.1 2)}"
BUILD="${2:?Usage: release.sh <version> <build>  (e.g. release.sh 1.1 2)}"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/Avatar.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG_NAME="Aaavatar-${VERSION}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
SCHEME="Avatar"

# Sparkle sign_update — pin to a stable cache path so the macOS Keychain ACL
# approval ("Always Allow access to this private key") survives across Xcode
# rebuilds. DerivedData paths change per workspace state, and the ACL is
# bound to the full file path, so a fresh `find … head -1` would re-prompt
# every release. Override with SIGN_UPDATE_PATH if needed.
SIGN_UPDATE_CACHE_DIR="$HOME/Library/Caches/avatar-release"
SIGN_UPDATE="$SIGN_UPDATE_CACHE_DIR/sign_update"
if [[ ! -x "$SIGN_UPDATE" || -n "${SIGN_UPDATE_PATH:-}" ]]; then
  SIGN_UPDATE_SRC="${SIGN_UPDATE_PATH:-$(find ~/Library/Developer/Xcode/DerivedData -path '*/artifacts/sparkle/Sparkle/bin/sign_update' -type f 2>/dev/null | head -1)}"
  if [[ -z "$SIGN_UPDATE_SRC" ]]; then
    echo "❌ sign_update not found. Build the project in Xcode (or set SIGN_UPDATE_PATH)."
    exit 1
  fi
  echo "→ Pinning sign_update to $SIGN_UPDATE..."
  mkdir -p "$SIGN_UPDATE_CACHE_DIR"
  cp "$SIGN_UPDATE_SRC" "$SIGN_UPDATE"
  chmod +x "$SIGN_UPDATE"
fi

echo "📦 Releasing Avatar v${VERSION} (build ${BUILD})"

# 1. Bump version in project.yml
echo "→ Bumping version in project.yml..."
sed -i '' "s/MARKETING_VERSION: .*/MARKETING_VERSION: \"${VERSION}\"/" "$PROJECT_DIR/project.yml"
sed -i '' "s/CURRENT_PROJECT_VERSION: .*/CURRENT_PROJECT_VERSION: \"${BUILD}\"/" "$PROJECT_DIR/project.yml"

# 2. Regenerate Xcode project
echo "→ xcodegen generate..."
cd "$PROJECT_DIR"
xcodegen generate

# 3. Archive
echo "→ Archiving..."
rm -rf "$BUILD_DIR"
xcodebuild \
  -project Avatar.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  archive

# 4. Export
echo "→ Exporting..."
# Minimal export-options plist
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
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

# 5. Build DMG (styled — background, positioned icons, Applications shortcut)
echo "→ Building DMG..."
if ! command -v create-dmg >/dev/null 2>&1; then
  echo "❌ create-dmg not found. Install with: brew install create-dmg"
  exit 1
fi

DMG_BACKGROUND="$PROJECT_DIR/scripts/dmg-assets/background.tiff"
if [[ ! -f "$DMG_BACKGROUND" ]]; then
  echo "→ Rendering DMG background..."
  python3 "$PROJECT_DIR/scripts/dmg-assets/build-background.py"
fi

rm -f "$DMG_PATH"
create-dmg \
  --volname "Aaavatar" \
  --background "$DMG_BACKGROUND" \
  --window-size 660 420 \
  --icon-size 128 \
  --icon "Aaavatar.app" 165 215 \
  --app-drop-link 495 215 \
  --hide-extension "Aaavatar.app" \
  --no-internet-enable \
  "$DMG_PATH" \
  "$EXPORT_DIR/Aaavatar.app"

# 6. Notarize (DMG)
echo "→ Notarizing..."
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "AC_PASSWORD" \
  --wait

# 7. Staple onto the DMG itself (Gatekeeper accepts this offline)
echo "→ Stapling..."
xcrun stapler staple "$DMG_PATH"

# 8. EdDSA signature
echo "→ Signing with EdDSA..."
SIGNATURE_OUTPUT=$("$SIGN_UPDATE" "$DMG_PATH")
echo "   $SIGNATURE_OUTPUT"

# Parse edSignature and length
ED_SIGNATURE=$(echo "$SIGNATURE_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
LENGTH=$(stat -f%z "$DMG_PATH")

# 9. Update appcast
#    BSD `sed` chokes on multi-line `a\` inserts (the heredoc payload has
#    embedded newlines, which `sed` reads as the start of new commands).
#    Use Python to do a literal "insert after the first <channel>" instead.
echo "→ Updating appcast..."
PUBDATE=$(date -R)
cd "$PROJECT_DIR"
APPCAST_PATH="$PROJECT_DIR/appcast.xml" \
APPCAST_VERSION="$VERSION" \
APPCAST_BUILD="$BUILD" \
APPCAST_PUBDATE="$PUBDATE" \
APPCAST_LENGTH="$LENGTH" \
APPCAST_DMG_NAME="$DMG_NAME" \
APPCAST_ED_SIGNATURE="$ED_SIGNATURE" \
python3 - <<'PY'
import os
path = os.environ["APPCAST_PATH"]
item = (
    "    <item>\n"
    f"      <title>Version {os.environ['APPCAST_VERSION']}</title>\n"
    f"      <pubDate>{os.environ['APPCAST_PUBDATE']}</pubDate>\n"
    f"      <sparkle:version>{os.environ['APPCAST_BUILD']}</sparkle:version>\n"
    f"      <sparkle:shortVersionString>{os.environ['APPCAST_VERSION']}</sparkle:shortVersionString>\n"
    "      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>\n"
    "      <enclosure\n"
    f"        url=\"https://github.com/Square-One-Official/Avatar/releases/download/v{os.environ['APPCAST_VERSION']}/{os.environ['APPCAST_DMG_NAME']}\"\n"
    f"        length=\"{os.environ['APPCAST_LENGTH']}\"\n"
    "        type=\"application/x-apple-diskimage\"\n"
    f"        sparkle:edSignature=\"{os.environ['APPCAST_ED_SIGNATURE']}\" />\n"
    "    </item>\n"
)
with open(path) as f:
    text = f.read()
needle = "<channel>"
i = text.index(needle) + len(needle)
# Skip past the trailing newline so the inserted block lines up with siblings.
if text[i:i+1] == "\n":
    i += 1
text = text[:i] + item + text[i:]
with open(path, "w") as f:
    f.write(text)
PY

# Mirror the appcast into the backend deploy so api.aaavatar.nl/appcast.xml
# stays in sync (audit HIGH #10 — self-hosted Sparkle feed). Old builds
# pinned to the GitHub URL keep using the file under repo root; new
# builds use the backend-served copy and benefit from TLS pinning.
cp "$PROJECT_DIR/appcast.xml" "$PROJECT_DIR/backend/api/_appcast.xml"

# 10. GitHub Release
#     Idempotent: if the tag already exists (re-running for a higher BUILD
#     under the same MARKETING_VERSION, e.g. shipping a hotfix without
#     bumping the public version), upload the new DMG over the old asset
#     instead of failing.
echo "→ Creating GitHub Release..."
# Stable-named copy so https://github.com/Square-One-Official/Avatar/releases/latest/download/Aaavatar.dmg
# always resolves to the newest release. The website (Framer) links to that URL,
# so it never has to be updated per release.
STABLE_DMG_PATH="$BUILD_DIR/Aaavatar.dmg"
cp "$DMG_PATH" "$STABLE_DMG_PATH"

if gh release view "v${VERSION}" >/dev/null 2>&1; then
  echo "   release v${VERSION} already exists — clobbering DMG assets"
  gh release upload "v${VERSION}" "$DMG_PATH" "$STABLE_DMG_PATH" --clobber
else
  gh release create "v${VERSION}" "$DMG_PATH" "$STABLE_DMG_PATH" \
    --title "Aaavatar v${VERSION}" \
    --generate-notes
fi

echo ""
echo "✅ Release v${VERSION} published!"
echo ""
echo "Don't forget:"
echo "  1. Verify appcast.xml + backend/api/_appcast.xml (both updated)"
echo "     and commit + push"
