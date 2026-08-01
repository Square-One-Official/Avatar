#!/bin/bash
# Aaavatar 2.0 Definition-of-Done-check: beide app-targets bouwen en alle
# package-tests draaien. Draai vanuit de repo-root (of een worktree-root).
set -euo pipefail

cd "$(dirname "$0")/.."

DERIVED="${DERIVED_DATA:-build/dd}"

echo "==> reduce-motion-guard (E53.4)"
bash scripts/check-motion.sh

echo "==> icoongrootte-guard (E53.9)"
bash scripts/check-icon-sizes.sh

echo "==> xcodegen"
xcodegen generate

echo "==> build Avatar (v1)"
xcodebuild -project Avatar.xcodeproj -scheme Avatar \
  -configuration Debug -derivedDataPath "$DERIVED" build | tail -1

echo "==> build Avatar2"
xcodebuild -project Avatar.xcodeproj -scheme Avatar2 \
  -configuration Debug -derivedDataPath "$DERIVED" build | tail -1

echo "==> tests Avatar2 (unit, gehost in Aaavatar 2.app)"
xcodebuild -project Avatar.xcodeproj -scheme Avatar2 \
  -configuration Debug -derivedDataPath "$DERIVED" test | tail -1

echo "==> tests AvatarKit"
swift test --package-path AvatarKit

echo "==> tests AvatarUI"
swift test --package-path AvatarUI

echo "==> alles groen"
