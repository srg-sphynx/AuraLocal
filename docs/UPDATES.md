# Shipping updates (Sparkle OTA)

Aura Local auto-updates with [Sparkle 2](https://sparkle-project.org). The app
polls an **appcast** (an RSS feed of releases) in the background; when a newer
version is listed, Sparkle downloads the archive, verifies its **EdDSA
signature**, and installs it with the standard "A new version is available"
flow. There is also a **Check for Updates…** menu item and a **Software Updates**
card in Settings.

This document is the operator's guide: how it's wired, the one-time setup, and
the per-release publishing steps.

## Live configuration (already set up)

The channel is provisioned — you don't need to redo the one-time setup:

- **Signing key:** an EdDSA keypair exists; the private key is in the `srg-sphynx`
  login **Keychain**, and the matching public key is in `Info.plist`
  (`SUPublicEDKey = Ss7+OduyDAmX5d6ShXvV1kHGGy1iWSMQLxwms1SOGD8=`).
  **Back the private key up** (`generate_keys -x sparkle_private_key.pem`) and keep
  it safe — losing it means no future update can be signed.
- **Feed:** `SUFeedURL = https://srg-sphynx.github.io/AuraLocal/appcast.xml`, served
  from the repo's **`gh-pages`** branch (which holds only `appcast.xml`, a tiny
  `index.html`, and `.nojekyll`).
- **Binaries:** each version's `.dmg` is attached to a **GitHub Release** (tag
  `vX.Y.Z`); the appcast's `<enclosure url>` points at that release asset.

So a release is: build DMG → attach to a Release → sign into `appcast.xml` → push
`gh-pages`. The [`Packaging/release_update.sh`](../Packaging/release_update.sh)
note at the end automates most of it.

---

## How it's wired

| Piece | Where |
| --- | --- |
| Sparkle dependency | `Package.swift` (SPM: `sparkle-project/Sparkle`) |
| Runtime wrapper | [`Sources/AuraLocal/Services/Updates/UpdaterService.swift`](../Sources/AuraLocal/Services/Updates/UpdaterService.swift) |
| Menu + Settings UI | `AuraApp.swift` (Check for Updates…), `SettingsView.swift` (Software Updates card) |
| Feed URL & public key | `Packaging/Info.plist` → `SUFeedURL`, `SUPublicEDKey` |
| Framework bundling & signing | `Packaging/build_app.sh` |
| Library-validation entitlement | `Packaging/AuraLocal.entitlements` |

The relevant `Info.plist` keys:

```xml
<key>SUFeedURL</key>       <string>https://srg-sphynx.github.io/AuraLocal/appcast.xml</string>
<key>SUPublicEDKey</key>   <string>REPLACE_WITH_YOUR_SPARKLE_ED25519_PUBLIC_KEY</string>
<key>SUEnableAutomaticChecks</key>       <true/>
<key>SUScheduledCheckInterval</key>      <integer>86400</integer>  <!-- daily -->
<key>SUAutomaticallyUpdate</key>         <false/>                   <!-- ask before installing -->
```

Sparkle's command-line tools ship inside the resolved SPM artifact:

```
.build/artifacts/sparkle/Sparkle/bin/
    generate_keys       # one-time: create the signing keypair
    sign_update         # sign a single archive
    generate_appcast    # build/refresh appcast.xml from a folder of archives
```

> Tip: add that folder to your `PATH` for the current shell, e.g.
> `export PATH="$PWD/.build/artifacts/sparkle/Sparkle/bin:$PATH"`
> (run `swift build` once so the artifact is downloaded).

---

## One-time setup

### 1. Generate the signing keypair

```bash
swift build                                   # ensures the tools are downloaded
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```

This stores the **private key in your login Keychain** (never commit it) and
prints the **public key**. Copy the public key into `Packaging/Info.plist`:

```xml
<key>SUPublicEDKey</key>
<string>«the base64 public key printed by generate_keys»</string>
```

> Back up the private key somewhere safe:
> `generate_keys -x sparkle_private_key.pem` exports it. If you lose it you can
> never sign a compatible update again and every user has to reinstall manually.

### 2. Pick where the appcast + archives live

`SUFeedURL` is already set to a GitHub Pages URL:
`https://srg-sphynx.github.io/AuraLocal/appcast.xml`. The simplest, most robust
layout is to host **both** `appcast.xml` and the `.dmg` files in the **same**
directory so every download URL shares one prefix. Any static host works
(GitHub Pages, S3, Cloudflare R2, a plain web server). If you change the URL,
update `SUFeedURL` and ship a build with the new value before switching hosts.

Enable GitHub Pages for this repo (Settings → Pages) serving from either the
`gh-pages` branch or the `/docs` folder of `main`. The examples below assume a
top-level `updates/` folder published at the Pages root.

---

## Publishing a new version

### 1. Bump the version

Edit **both** keys in `Packaging/Info.plist` (they can match):

```xml
<key>CFBundleShortVersionString</key>  <string>3.2.0</string>   <!-- marketing version -->
<key>CFBundleVersion</key>             <string>3.2.0</string>   <!-- build number Sparkle compares -->
```

Add a section to `CHANGELOG.md`. Sparkle can show release notes in the update
prompt (see step 4).

### 2. Build the signed DMG

```bash
bash Packaging/build_app.sh
```

This produces `Builds/AuraLocal-v<version>.dmg` with Sparkle embedded and
ad-hoc–signed. (The DMG is what you'll distribute; Sparkle can update from a
`.dmg` or a `.zip` of the `.app`.)

### 3. Refresh the appcast (signs automatically)

`generate_appcast` scans a folder of archives, computes each one's EdDSA
signature (using the Keychain private key) and size, and writes `appcast.xml`:

```bash
BIN=.build/artifacts/sparkle/Sparkle/bin
mkdir -p updates
cp "Builds/AuraLocal-v3.2.0.dmg" updates/

"$BIN/generate_appcast" \
  --download-url-prefix "https://srg-sphynx.github.io/AuraLocal/updates/" \
  updates/
# → writes updates/appcast.xml with an <item> for every DMG in updates/
```

Keep older DMGs in `updates/` so users on very old versions still have a valid
upgrade path (Sparkle picks the newest item they qualify for).

> Prefer GitHub Releases for hosting the binaries instead? Host only
> `appcast.xml` on Pages, upload the DMG to a Release, then sign it manually:
> `"$BIN/sign_update Builds/AuraLocal-v3.2.0.dmg"` prints
> `sparkle:edSignature="…" length="…"`. Paste those into a hand-written `<item>`
> whose `<enclosure url>` points at the Release asset URL. `generate_appcast` is
> just the automated version of this.

### 4. (Optional) Release notes

Put an HTML file next to the DMG named after it — `updates/AuraLocal-v3.2.0.html`
— and `generate_appcast` links it as that item's `<description>`. Sparkle renders
it in the update dialog.

### 5. Publish

Commit and push the `updates/` folder (or upload it to your host):

```bash
git add updates/ Packaging/Info.plist CHANGELOG.md
git commit -m "Release 3.2.0"
git push
# GitHub Pages serves updates/appcast.xml within a minute or two.
```

Installed copies will pick it up on their next scheduled check, or immediately
via **Check for Updates…**.

---

## Verifying before you ship

- **Appcast reachable:** open `SUFeedURL` in a browser — it must return the XML,
  not an HTML 404 page.
- **Signature present:** each `<item>` has a non-empty
  `sparkle:edSignature` and a `length` matching the DMG's byte size.
- **Version ordering:** the new item's `sparkle:version` (from `CFBundleVersion`)
  is greater than the currently installed build.
- **End-to-end test:** install the *previous* version, then publish the new one
  and confirm the app offers and installs it. Sparkle also logs to Console —
  filter by the process name if a check silently does nothing.

## Notarization (recommended for public distribution)

These builds are **ad-hoc signed**, so first-run still requires the
right-click → Open Gatekeeper bypass (see `Packaging/DMG-README.txt`), and the
`com.apple.security.cs.disable-library-validation` entitlement is what lets the
ad-hoc Sparkle framework load. For a smoother experience, sign with a
**Developer ID Application** certificate and notarize:

1. In `build_app.sh`, replace `--sign -` with `--sign "Developer ID Application: …"`.
2. `xcrun notarytool submit Builds/AuraLocal-v<version>.dmg --keychain-profile … --wait`
3. `xcrun stapler staple Builds/AuraLocal-v<version>.dmg`

Sparkle's EdDSA signature is independent of Apple code signing — you need both:
Apple signing/notarization for Gatekeeper, EdDSA for Sparkle's own verification.
