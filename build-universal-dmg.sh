#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="Wolffe TV.app"
BUNDLE="build/$APP"
DMG="build/Wolffe-TV-v4-universal.dmg"
rm -rf build .build
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

swift build -c release --arch arm64
cp .build/arm64-apple-macosx/release/WolffeTV build/WolffeTV-arm64
swift build -c release --arch x86_64
cp .build/x86_64-apple-macosx/release/WolffeTV build/WolffeTV-x86_64
lipo -create build/WolffeTV-arm64 build/WolffeTV-x86_64 -output "$BUNDLE/Contents/MacOS/WolffeTV"
cp Info.plist "$BUNDLE/Contents/Info.plist"

# Ad-hoc signing is suitable for local testing only. Public releases should use Developer ID and notarization.
codesign --force --deep --sign - "$BUNDLE"
mkdir -p build/dmg
cp -R "$BUNDLE" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname "Wolffe TV v4" -srcfolder build/dmg -ov -format UDZO "$DMG"
echo "Built: $DMG"
