#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/release.sh [version]
# Example: ./scripts/release.sh 0.1.0
#
# Creates a GitHub release with the Trellis.app zip attached.
# If no version is provided, reads from Resources/Info.plist.

VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
  VERSION=$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
fi

TAG="v${VERSION}"
ZIP_NAME="Trellis-${VERSION}-macos-arm64.zip"
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

# Create git tag
echo "==> Tagging ${TAG}..."
git tag "${TAG}"
git push origin "${TAG}"

# Create GitHub release
echo "==> Creating GitHub release..."
gh release create "${TAG}" \
  "${BUILD_DIR}/${ZIP_NAME}" \
  --title "Trellis ${TAG}" \
  --notes "$(cat <<EOF
## Trellis ${VERSION}

> **Note**: This build is unsigned. After downloading, run:
> \`\`\`
> xattr -d com.apple.quarantine Trellis.app
> \`\`\`

### Requirements
- macOS 14.0+
- Apple Silicon (arm64)
EOF
)"

echo "==> Done! https://github.com/d-kimuson/trellis/releases/tag/${TAG}"
