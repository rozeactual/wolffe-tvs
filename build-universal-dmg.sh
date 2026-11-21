#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP_NAME="Wolffe TV.app"; EXECUTABLE_NAME="WolffeTV"; BUILD_ROOT="$PWD/build"
APP_BUNDLE="$BUILD_ROOT/$APP_NAME"; DMG_STAGING="$BUILD_ROOT/dmg"; DMG_PATH="$BUILD_ROOT/Wolffe-TV-v4-alpha3.6.1-universal.dmg"
fail(){ printf '\nERROR: %s\n' "$1" >&2; exit 1; }

printf 'Wolffe TV v4 Alpha 3.6.1 build preflight\n--------------------------------------\n'
DEV="$(xcode-select -p 2>/dev/null || true)"
[[ "$DEV" == *"Xcode.app/Contents/Developer" ]] || fail "Full Xcode is not selected. Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
for cmd in swift diskutil codesign sips iconutil lipo; do command -v "$cmd" >/dev/null || fail "$cmd was not found."; done
for file in Package.swift Info.plist AppIcon-source.png; do [[ -f "$file" ]] || fail "$file is missing."; done
printf '✓ Full Xcode selected\n✓ Swift and packaging tools available\n✓ Icon source found\n\n'

rm -rf "$BUILD_ROOT" .build
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
ARGS=(-c release --product "$EXECUTABLE_NAME" --arch arm64 --arch x86_64)
swift build "${ARGS[@]}"
BIN_DIR="$(swift build "${ARGS[@]}" --show-bin-path)"; SOURCE_BINARY="$BIN_DIR/$EXECUTABLE_NAME"
[[ -x "$SOURCE_BINARY" ]] || fail "SwiftPM did not produce $SOURCE_BINARY"
ARCHS="$(lipo -archs "$SOURCE_BINARY")"
[[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]] || fail "Expected arm64 and x86_64; found: $ARCHS"
cp "$SOURCE_BINARY" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"; chmod +x "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

ICONSET="$BUILD_ROOT/WolffeTV.iconset"; mkdir -p "$ICONSET"
make_icon(){ sips -z "$1" "$1" AppIcon-source.png --out "$ICONSET/$2" >/dev/null; }
make_icon 16 icon_16x16.png; make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png; make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png; make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png; make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png; make_icon 1024 icon_512x512@2x.png
iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/WolffeTV.icns"
[[ -s "$APP_BUNDLE/Contents/Resources/WolffeTV.icns" ]] || fail "The application icon was not generated."
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP_BUNDLE/Contents/Info.plist" | grep -q 'WolffeTV.icns' || fail "Info.plist does not reference WolffeTV.icns."

codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
mkdir -p "$DMG_STAGING"; cp -R "$APP_BUNDLE" "$DMG_STAGING/"; ln -s /Applications "$DMG_STAGING/Applications"
rm -f "$DMG_PATH"
diskutil image create from --volumeName "Wolffe TV v4 Alpha 3.6.1" --format UDZO "$DMG_STAGING" "$DMG_PATH"
printf '\nSUCCESS\nArchitectures: %s\nApp: %s\nIcon: included and verified\nDMG: %s\n' "$ARCHS" "$APP_BUNDLE" "$DMG_PATH"
