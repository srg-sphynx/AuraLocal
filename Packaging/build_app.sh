#!/bin/bash
# Builds Aura Local, assembles a signed .app bundle, and produces a DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/Packaging"
APP_NAME="Aura Local"
EXEC_NAME="AuraLocal"
BUILD_DIR="$ROOT/.build/release"
DIST="$ROOT/.dist"
APP="$DIST/$APP_NAME.app"
BUILDS_DIR="${1:-$ROOT/../Builds}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PKG/Info.plist" 2>/dev/null || echo '1.0.0')"

echo "▸ Building release binary (v$VERSION)…"
cd "$ROOT"
swift build -c release

echo "▸ Generating app icon…"
ICON_WORK="$DIST/iconwork"
rm -rf "$DIST"; mkdir -p "$ICON_WORK"
swift "$PKG/generate_icon.swift" "$ICON_WORK/icon_1024.png"

ICONSET="$ICON_WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 64 128 256 512; do
  sips -z $s $s     "$ICON_WORK/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png"     >/dev/null
  d=$((s*2))
  sips -z $d $d     "$ICON_WORK/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png"  >/dev/null
done
cp "$ICON_WORK/icon_1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$ICON_WORK/AppIcon.icns"

echo "▸ Assembling bundle…"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/$EXEC_NAME" "$APP/Contents/MacOS/$EXEC_NAME"
cp "$PKG/Info.plist" "$APP/Contents/Info.plist"
cp "$ICON_WORK/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▸ Code signing (ad-hoc)…"
codesign --force --deep --options runtime \
  --entitlements "$PKG/AuraLocal.entitlements" \
  --sign - "$APP" 2>/dev/null || \
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP" && echo "  ✓ signature valid"

echo "▸ Creating DMG…"
mkdir -p "$BUILDS_DIR"
DMG_STAGE="$DIST/dmg"
rm -rf "$DMG_STAGE"; mkdir -p "$DMG_STAGE"
cp -R "$APP" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
DMG_PATH="$BUILDS_DIR/AuraLocal-v$VERSION.dmg"
# Replace any prior versioned DMGs so the folder holds only the current build.
rm -f "$BUILDS_DIR"/AuraLocal-v*.dmg
hdiutil create -volname "Aura Local" -srcfolder "$DMG_STAGE" \
  -ov -format UDZO "$DMG_PATH" >/dev/null
echo "  ✓ DMG → $DMG_PATH"

# Also drop a copy of the raw .app next to the DMG for direct use.
rm -rf "$BUILDS_DIR/$APP_NAME.app"
cp -R "$APP" "$BUILDS_DIR/$APP_NAME.app"

echo "▸ Done."
echo "  App:  $BUILDS_DIR/$APP_NAME.app"
echo "  DMG:  $DMG_PATH"
