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

# Sparkle sign_update — searches DerivedData, override with SIGN_UPDATE_PATH
SIGN_UPDATE="${SIGN_UPDATE_PATH:-$(find ~/Library/Developer/Xcode/DerivedData -name sign_update -type f 2>/dev/null | head -1)}"
if [[ -z "$SIGN_UPDATE" ]]; then
  echo "❌ sign_update not found. Set SIGN_UPDATE_PATH or build the project in Xcode first."
  exit 1
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

# 5. Build DMG
echo "→ Building DMG..."
hdiutil create -volname "Aaavatar" \
  -srcfolder "$EXPORT_DIR/Avatar.app" \
  -ov -format UDZO \
  "$DMG_PATH"

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
echo "→ Updating appcast..."
PUBDATE=$(date -R)
NEW_ITEM=$(cat <<ITEM
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUBDATE}</pubDate>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure
        url="https://github.com/thierrzz/Avatar/releases/download/v${VERSION}/${DMG_NAME}"
        length="${LENGTH}"
        type="application/x-apple-diskimage"
        sparkle:edSignature="${ED_SIGNATURE}" />
    </item>
ITEM
)

# Insert the new item right after <channel> (above existing items)
cd "$PROJECT_DIR"
sed -i '' "/<channel>/a\\
${NEW_ITEM}
" appcast.xml

# 10. GitHub Release
echo "→ Creating GitHub Release..."
gh release create "v${VERSION}" "$DMG_PATH" \
  --title "Aaavatar v${VERSION}" \
  --generate-notes

echo ""
echo "✅ Release v${VERSION} published!"
echo ""
echo "Don't forget:"
echo "  1. Verify appcast.xml and commit + push"
