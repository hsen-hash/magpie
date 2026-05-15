#!/usr/bin/env bash
# Build a redistributable Magpie .dmg.
# Output: <repo>/Magpie-<version>.dmg
#
# Usage:  ./tools/make_dmg.sh [version]   # version defaults to 0.1

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1}"
APP_NAME="Magpie"
APP_PATH="build/${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_DIR="build/dmg-staging"
VOLUME_NAME="${APP_NAME} ${VERSION}"

echo "→ ensuring fresh build"
./build.sh >/dev/null

if [[ ! -d "$APP_PATH" ]]; then
    echo "✖  $APP_PATH not found — build.sh did not produce the app bundle" >&2
    exit 1
fi

echo "→ assembling DMG staging at $DMG_DIR"
rm -rf "$DMG_DIR" "$DMG_NAME"
mkdir -p "$DMG_DIR"
cp -R "$APP_PATH" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

echo "→ creating compressed DMG ($VOLUME_NAME)"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "$DMG_NAME" >/dev/null

rm -rf "$DMG_DIR"

SIZE=$(du -h "$DMG_NAME" | cut -f1)
echo "→ done: $DMG_NAME ($SIZE)"
echo
echo "Next steps:"
echo "  1. Test:    open $DMG_NAME      # mount, drag Magpie.app to Applications"
echo "  2. Release: gh release create v${VERSION} $DMG_NAME --title 'Magpie v${VERSION}' --notes 'See README.'"
