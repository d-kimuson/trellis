#!/usr/bin/env bash
set -euo pipefail

# Patch ghostty build.zig to allow building libghostty.a on macOS
# without requiring iOS SDK (xcframework).

GHOSTTY_DIR="${1:-deps/ghostty}"

echo "Patching ghostty build for macOS-only libghostty..."

# 1. Remove the isDarwin guard so we can install .a directly on macOS
# Original: if (!config.target.result.os.tag.isDarwin()) {
# Patched:  if (true) {  // patched: allow macOS static lib
sed -i '' \
  's/if (!config.target.result.os.tag.isDarwin()) {/if (true) { \/\/ patched: allow macOS static lib/' \
  "$GHOSTTY_DIR/build.zig"

# 2. Guard the xcframework init behind emit_xcframework to avoid iOS SDK requirement
# Original: const xcframework = try buildpkg.GhosttyXCFramework.init(
# Patched:  wrap in if block
cat > /tmp/ghostty-xcframework-patch.py << 'PYEOF'
import re

with open("GHOSTTY_DIR/build.zig", "r") as f:
    content = f.read()

# Find and wrap the xcframework block in an if guard
old = '''    if (config.target.result.os.tag.isDarwin()) {
        // Ghostty xcframework
        const xcframework = try buildpkg.GhosttyXCFramework.init(
            b,
            &deps,
            config.xcframework_target,
        );
        if (config.emit_xcframework) {'''

new = '''    if (config.target.result.os.tag.isDarwin() and config.emit_xcframework) {
        // Ghostty xcframework (patched: only init when explicitly requested)
        const xcframework = try buildpkg.GhosttyXCFramework.init(
            b,
            &deps,
            config.xcframework_target,
        );
        if (config.emit_xcframework) {'''

content = content.replace(old, new)

with open("GHOSTTY_DIR/build.zig", "w") as f:
    f.write(content)

print("Patched xcframework guard")
PYEOF

sed -i '' "s|GHOSTTY_DIR|$GHOSTTY_DIR|g" /tmp/ghostty-xcframework-patch.py
python3 /tmp/ghostty-xcframework-patch.py

echo "Patch applied successfully!"
echo "You can now build with: zig build -Dapp-runtime=none -Doptimize=ReleaseFast"
