#!/bin/bash
# One-command release: build the DMG, attach it to a GitHub Release, sign it into
# the Sparkle appcast, and publish the appcast to the gh-pages branch.
#
# Prereqs (already set up once):
#   • EdDSA private key in the Keychain (Sparkle `generate_keys`), public key in
#     Packaging/Info.plist as SUPublicEDKey.
#   • `gh` authenticated for the srg-sphynx/AuraLocal repo.
#   • GitHub Pages serving the gh-pages branch root (feed = SUFeedURL).
#
# Usage: bump CFBundleShortVersionString/CFBundleVersion in Packaging/Info.plist
#        first, then run:  bash Packaging/release_update.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/Packaging"
REPO="srg-sphynx/AuraLocal"
BUILDS_DIR="$ROOT/../Builds"
BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PKG/Info.plist")"
TAG="v$VERSION"
DMG="$BUILDS_DIR/AuraLocal-v$VERSION.dmg"
DL_PREFIX="https://github.com/$REPO/releases/download/$TAG/"

command -v gh >/dev/null || { echo "✗ gh CLI not found"; exit 1; }
[ -x "$BIN/generate_appcast" ] || { echo "✗ Sparkle tools missing — run 'swift build' first"; exit 1; }

echo "▸ Building $TAG…"
bash "$PKG/build_app.sh"
[ -f "$DMG" ] || { echo "✗ expected $DMG"; exit 1; }

echo "▸ Publishing GitHub Release $TAG…"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" "$DMG" --repo "$REPO" --clobber
else
  gh release create "$TAG" "$DMG" --repo "$REPO" --target main \
    --title "Aura Local $VERSION" --notes "See CHANGELOG.md."
fi

echo "▸ Signing appcast…"
STAGE="$(mktemp -d)"
cp "$DMG" "$STAGE/"
# Reuse an existing appcast so older items are preserved (Sparkle keeps the whole
# version history in one feed). Pull the current one down if present.
curl -fsSL "https://srg-sphynx.github.io/AuraLocal/appcast.xml" -o "$STAGE/appcast.xml" 2>/dev/null || true
"$BIN/generate_appcast" --download-url-prefix "$DL_PREFIX" "$STAGE"

echo "▸ Pushing appcast to gh-pages…"
WORK="$(mktemp -d)"
git clone --quiet --branch gh-pages "https://github.com/$REPO.git" "$WORK"
cp "$STAGE/appcast.xml" "$WORK/appcast.xml"
git -C "$WORK" add appcast.xml
git -C "$WORK" -c user.name="srg-sphynx" -c user.email="saketa369@gmail.com" \
    commit -q -m "Publish appcast for $VERSION" || { echo "  (no appcast change)"; }
git -C "$WORK" push --quiet origin gh-pages
rm -rf "$STAGE" "$WORK"

echo "▸ Done. Feed: https://srg-sphynx.github.io/AuraLocal/appcast.xml"
echo "  Installed copies pick up $VERSION on their next check (Pages may take ~1 min)."
