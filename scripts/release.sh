#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/release.sh [version]
# Example: ./scripts/release.sh 0.1.0
#
# Creates a GitHub release with Trellis.app zip and dmg attached.
# If no version is provided, reads from Resources/Info.plist.

VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
  VERSION=$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
fi

TAG="v${VERSION}"
ZIP_NAME="Trellis-${VERSION}-macos-arm64.zip"
DMG_NAME="Trellis-${VERSION}-macos-arm64.dmg"
BUILD_DIR=".build"
APP_BUNDLE="${BUILD_DIR}/Trellis.app"

echo "==> Releasing Trellis ${TAG}"

# Ensure working tree is clean
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Error: Working tree is dirty. Commit or stash changes first."
  exit 1
fi

# Check if tag already exists
if git rev-parse "${TAG}" &>/dev/null; then
  echo "Error: Tag ${TAG} already exists."
  exit 1
fi

# Update Info.plist version if needed
CURRENT_VERSION=$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
if [[ "$CURRENT_VERSION" != "$VERSION" ]]; then
  echo "==> Updating Info.plist: ${CURRENT_VERSION} -> ${VERSION}..."
  plutil -replace CFBundleShortVersionString -string "${VERSION}" Resources/Info.plist
  git add Resources/Info.plist
  git commit -m "chore: bump version to ${VERSION}"
fi

# Build
echo "==> Building..."
make clean
make app

# Verify .app bundle exists
if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Error: ${APP_BUNDLE} not found."
  exit 1
fi

# Create zip (ditto preserves macOS metadata better than zip)
echo "==> Creating ${ZIP_NAME}..."
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "${BUILD_DIR}/${ZIP_NAME}"

# Create dmg
# Staging dir contains the .app + a symlink to /Applications for drag-install UX
echo "==> Creating ${DMG_NAME}..."
DMG_STAGING="${BUILD_DIR}/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create \
  -volname "Trellis" \
  -srcfolder "$DMG_STAGING" \
  -ov -format UDZO \
  "${BUILD_DIR}/${DMG_NAME}"
rm -rf "$DMG_STAGING"

# Create git tag
echo "==> Tagging ${TAG}..."
git tag "${TAG}"
git push origin "${TAG}"

# Create GitHub release
echo "==> Creating GitHub release..."
gh release create "${TAG}" \
  "${BUILD_DIR}/${DMG_NAME}" \
  "${BUILD_DIR}/${ZIP_NAME}" \
  --title "Trellis ${TAG}" \
  --notes "$(cat <<EOF
## Install

1. Open \`Trellis-${VERSION}-macos-arm64.dmg\`
2. Drag Trellis to Applications

**Note**: Trellis is not signed with an Apple Developer certificate. macOS will block the app on first launch with "Trellis is damaged and can't be opened." This is a Gatekeeper restriction, not an actual problem with the app.

To run it, remove the quarantine attribute after copying to Applications:

\`\`\`bash
xattr -d com.apple.quarantine /Applications/Trellis.app
\`\`\`

## Requirements
- macOS 14.0+
- Apple Silicon (arm64)
EOF
)"

echo "==> Done! https://github.com/d-kimuson/trellis/releases/tag/${TAG}"
