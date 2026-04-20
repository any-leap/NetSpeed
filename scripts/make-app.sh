#!/bin/bash
# Wrap the SPM binary in a proper NetSpeed.app bundle for DMG distribution.
# Usage: scripts/make-app.sh <version>
set -euo pipefail

VERSION="${1:-dev}"
APP="dist/NetSpeed.app"
BINARY=".build/release/NetSpeed"

if [ ! -x "$BINARY" ]; then
    echo "error: $BINARY not found. Run 'make build' first." >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/NetSpeed"
cp Sources/NetSpeed/Info.plist "$APP/Contents/Info.plist"

# Bump CFBundleVersion / CFBundleShortVersionString to match the release tag.
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION#v}" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION#v}" "$APP/Contents/Info.plist" 2>/dev/null || true

codesign --sign - --force --deep --timestamp=none "$APP"
echo "✓ built $APP (version $VERSION)"
