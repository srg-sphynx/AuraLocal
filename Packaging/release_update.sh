#!/bin/bash
# One-command release: build the DMG, attach it to a GitHub Release, sign it into
# the Sparkle appcast, and publish the appcast to the gh-pages branch.
#
# Prereqs (set up once):
#   • Packaging/release.env — the channel identity (feed URL, Sparkle public key,
#     target repo, commit identity). Gitignored; see release.env.example.
#   • EdDSA private key in your login Keychain (Sparkle `generate_keys`).
#   • `gh` authenticated for the repo named by RELEASE_REPO.
#   • GitHub Pages serving the gh-pages branch root (feed = SU_FEED_URL).
#
# Usage: bump CFBundleShortVersionString/CFBundleVersion in Packaging/Info.plist
#        first, then run:  bash Packaging/release_update.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/Packaging"

# The publishing target is deliberately NOT in source control — a clone of this
# repository must not be able to push to the official release channel.
[ -f "$PKG/release.env" ] || {
  echo "✗ Packaging/release.env not found."
  echo "  cp Packaging/release.env.example Packaging/release.env and fill it in."
  exit 1
}
set -a; . "$PKG/release.env"; set +a
: "${RELEASE_REPO:?set RELEASE_REPO in Packaging/release.env}"
: "${SU_FEED_URL:?set SU_FEED_URL in Packaging/release.env}"

REPO="$RELEASE_REPO"
BUILDS_DIR="$ROOT/../Builds"
BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PKG/Info.plist")"
TAG="v$VERSION"
DMG="$BUILDS_DIR/AuraLocal-v$VERSION.dmg"
DL_PREFIX="https://github.com/$REPO/releases/download/$TAG/"

command -v gh >/dev/null || { echo "✗ gh CLI not found"; exit 1; }
[ -x "$BIN/generate_appcast" ] || { echo "✗ Sparkle tools missing — run 'swift build' first"; exit 1; }

# Preflight: every release MUST have a CHANGELOG entry for this version — it becomes
# the GitHub Release notes and the in-app "What's New". Extract the `## [VERSION] …`
# section (up to the next `## `). Abort if it's missing so we never ship blank notes.
NOTES_FILE="$(mktemp)"
awk -v ver="$VERSION" '
  /^## / { if (cap) exit; if (index($0, "[" ver "]") > 0) { cap=1; next } }
  cap { print }
' "$ROOT/CHANGELOG.md" > "$NOTES_FILE"
{ echo; echo "— Full changelog: https://github.com/$REPO/blob/main/CHANGELOG.md"; } >> "$NOTES_FILE"
if ! grep -q '[^[:space:]]' "$NOTES_FILE"; then
  echo "✗ CHANGELOG.md has no '## [$VERSION] — <date>' section. Add detailed release notes for $VERSION first."
  exit 1
fi

echo "▸ Building $TAG…"
bash "$PKG/build_app.sh"
[ -f "$DMG" ] || { echo "✗ expected $DMG"; exit 1; }

echo "▸ Publishing GitHub Release $TAG (notes from CHANGELOG)…"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" "$DMG" --repo "$REPO" --clobber
  gh release edit "$TAG" --repo "$REPO" --title "Aura Local $VERSION" --notes-file "$NOTES_FILE"
else
  gh release create "$TAG" "$DMG" --repo "$REPO" --target main \
    --title "Aura Local $VERSION" --notes-file "$NOTES_FILE"
fi
rm -f "$NOTES_FILE"

echo "▸ Signing appcast…"
STAGE="$(mktemp -d)"
cp "$DMG" "$STAGE/"
# Reuse an existing appcast so older items are preserved (Sparkle keeps the whole
# version history in one feed). Pull the current one down if present.
curl -fsSL "$SU_FEED_URL" -o "$STAGE/appcast.xml" 2>/dev/null || true
"$BIN/generate_appcast" --download-url-prefix "$DL_PREFIX" "$STAGE"

echo "▸ Pushing appcast to gh-pages…"
WORK="$(mktemp -d)"
git clone --quiet --branch gh-pages "https://github.com/$REPO.git" "$WORK"
cp "$STAGE/appcast.xml" "$WORK/appcast.xml"
git -C "$WORK" add appcast.xml
git -C "$WORK" -c user.name="${RELEASE_GIT_NAME:-release-bot}" \
              -c user.email="${RELEASE_GIT_EMAIL:-release-bot@users.noreply.github.com}" \
    commit -q -m "Publish appcast for $VERSION" || { echo "  (no appcast change)"; }
git -C "$WORK" push --quiet origin gh-pages
rm -rf "$STAGE" "$WORK"

echo "▸ Done. Feed: $SU_FEED_URL"
echo "  Installed copies pick up $VERSION on their next check (Pages may take ~1 min)."
