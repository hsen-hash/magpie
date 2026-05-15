#!/usr/bin/env bash
# Generate Magpie.icns from the procedural drawing in make_icon.swift.
set -euo pipefail
cd "$(dirname "$0")"

echo "→ rendering master 1024×1024 PNG"
swift make_icon.swift

ICONSET="Magpie.iconset"
rm -rf "$ICONSET"
mkdir "$ICONSET"

echo "→ resizing into iconset"
sips -z 16 16     Magpie-1024.png --out "$ICONSET/icon_16x16.png"     >/dev/null
sips -z 32 32     Magpie-1024.png --out "$ICONSET/icon_16x16@2x.png"  >/dev/null
sips -z 32 32     Magpie-1024.png --out "$ICONSET/icon_32x32.png"     >/dev/null
sips -z 64 64     Magpie-1024.png --out "$ICONSET/icon_32x32@2x.png"  >/dev/null
sips -z 128 128   Magpie-1024.png --out "$ICONSET/icon_128x128.png"   >/dev/null
sips -z 256 256   Magpie-1024.png --out "$ICONSET/icon_128x128@2x.png">/dev/null
sips -z 256 256   Magpie-1024.png --out "$ICONSET/icon_256x256.png"   >/dev/null
sips -z 512 512   Magpie-1024.png --out "$ICONSET/icon_256x256@2x.png">/dev/null
sips -z 512 512   Magpie-1024.png --out "$ICONSET/icon_512x512.png"   >/dev/null
cp Magpie-1024.png "$ICONSET/icon_512x512@2x.png"

echo "→ iconutil → Magpie.icns"
iconutil -c icns "$ICONSET" -o Magpie.icns
rm -rf "$ICONSET"
echo "→ done: tools/Magpie.icns"
