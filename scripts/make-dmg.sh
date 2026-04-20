#!/bin/bash
# Package dist/NetSpeed.app into a DMG with a drag-to-Applications layout.
# Usage: scripts/make-dmg.sh <version>
set -euo pipefail

VERSION="${1:-dev}"
APP="dist/NetSpeed.app"
DMG="dist/NetSpeed-${VERSION}.dmg"
STAGING=$(mktemp -d)

if [ ! -d "$APP" ]; then
    echo "error: $APP not found. Run scripts/make-app.sh first." >&2
    exit 1
fi

cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create \
    -volname "NetSpeed" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG" >/dev/null

rm -rf "$STAGING"
echo "✓ packaged $DMG"
