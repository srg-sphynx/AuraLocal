# Shipping updates (Sparkle OTA)

Aura Local auto-updates with [Sparkle 2](https://sparkle-project.org). The app
polls an **appcast** (an RSS feed of releases) in the background; when a newer
version is listed, Sparkle downloads the archive, verifies its **EdDSA
signature**, and installs it with the standard "A new version is available"
flow. There is also a **Check for Updates…** menu item and a **Software Updates**
card in Settings.

This document is the operator's guide: how it's wired, the one-time setup, and
the per-release publishing steps.

## Where the channel identity lives

> **The update channel is not described in this repository.** The appcast URL,
> the Sparkle public key, and the publishing target are read at build time from
> **`Packaging/release.env`**, which is gitignored. The tracked `Info.plist`
> carries only `__SU_FEED_URL__` / `__SU_PUBLIC_ED_KEY__` placeholders.
>
> This is deliberate: a clone of this repository must not be able to build an
> app that polls the official feed, nor publish to it. See
> [`Packaging/release.env.example`](../Packaging/release.env.example).

Set it up once:

```bash
cp Packaging/release.env.example Packaging/release.env
$EDITOR Packaging/release.env      # fill in SU_FEED_URL, SU_PUBLIC_ED_KEY, RELEASE_REPO
```

| Variable | Meaning |
| --- | --- |
| `SU_FEED_URL` | Appcast URL the shipped app polls (`Info.plist` → `SUFeedURL`) |
| `SU_PUBLIC_ED_KEY` | Base64 EdDSA **public** key (`Info.plist` → `SUPublicEDKey`) |
| `RELEASE_REPO` | `owner/repo` receiving the GitHub Release + gh-pages appcast |
| `RELEASE_GIT_NAME` / `RELEASE_GIT_EMAIL` | Commit identity for the automated appcast commit |

`build_app.sh` injects these into the bundle's `Info.plist`. **Build without
`release.env` and the feed keys are stripped and automatic checks stay off** —
the app still runs, it just never looks for updates.

The **private** key never appears in this file or the repository: it lives in
your login **Keychain**. Back it up (`generate_keys -x sparkle_private_key.pem`,
stored somewhere encrypted — `*.pem` is gitignored). Lose it and no future
update can ever be signed for already-installed copies.

**Binaries:** each version's `.dmg` is attached to a **GitHub Release** (tag
`vX.Y.Z`); the appcast's `<enclosure url>` points at that release asset.

So a release is: build DMG → attach to a Release → sign into `appcast.xml` → push
`gh-pages`. [`Packaging/release_update.sh`](../Packaging/release_update.sh)
automates all of it.

---

## How it's wired

| Piece | Where |
| --- | --- |
| Sparkle dependency | `Package.swift` (SPM: `sparkle-project/Sparkle`) |
| Runtime wrapper | [`Sources/AuraLocal/Services/Updates/UpdaterService.swift`](../Sources/AuraLocal/Services/Updates/UpdaterService.swift) |
| Menu + Settings UI | `AuraApp.swift` (Check for Updates…), `SettingsView.swift` (Software Updates card) |
| Feed URL & public key | `Packaging/release.env` (untracked) → injected by `build_app.sh` |
| Framework bundling & signing | `Packaging/build_app.sh` |
| Library-validation entitlement | `Packaging/AuraLocal.entitlements` |

The relevant `Info.plist` keys, **as tracked in git** (placeholders):

```xml
<key>SUFeedURL</key>       <string>__SU_FEED_URL__</string>
<key>SUPublicEDKey</key>   <string>__SU_PUBLIC_ED_KEY__</string>
<key>SUEnableAutomaticChecks</key>       <false/>                   <!-- enabled at build time -->
<key>SUScheduledCheckInterval</key>      <integer>86400</integer>   <!-- daily -->
<key>SUAutomaticallyUpdate</key>         <false/>                   <!-- ask before installing -->
```

At bundle time `build_app.sh` replaces the two placeholders with the values from
`release.env` and flips `SUEnableAutomaticChecks` to `true`. If `release.env` is
absent it deletes both keys instead, so an unconfigured build never ships a
dangling feed URL.

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
prints the **public key**. Put the public key in `Packaging/release.env` — *not*
in `Info.plist`, which is tracked:

```bash
SU_PUBLIC_ED_KEY="«the base64 public key printed by generate_keys»"
```

> Back up the private key somewhere safe:
> `generate_keys -x sparkle_private_key.pem` exports it. Store that export in a
> password manager or encrypted volume, never in the repo (`*.pem` is
> gitignored). If you lose it you can never sign a compatible update again and
> every user has to reinstall manually.

### 2. Pick where the appcast + archives live

Set `SU_FEED_URL` in `Packaging/release.env`. The simplest, most robust layout
is to host **both** `appcast.xml` and the `.dmg` files in the **same** directory
so every download URL shares one prefix. Any static host works (GitHub Pages,
S3, Cloudflare R2, a plain web server). If you change the URL, update
`SU_FEED_URL` and ship a build with the new value **before** switching hosts —
installed copies only learn the new feed by updating to a build that carries it.

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

**`Info.plist` is the single source of truth for the version.** The app reads
`CFBundleShortVersionString` at runtime (`AppInfo.version`) everywhere it's shown
(Settings → About, Software Updates, the "What's New" sheet), so you never edit a
version string anywhere else — don't hardcode it in the UI.

**A `CHANGELOG.md` entry is required, not optional.** Add a `## [<version>] — <date>`
section with detailed, user-facing notes. That one section is reused three ways:
GitHub Release notes, the in-app **What's New** viewer (the changelog is bundled
into the app), and — after an update — the one-time popup users see. `build_app.sh`
copies `CHANGELOG.md` into the app bundle, and `release_update.sh` **aborts** if the
current version has no changelog section, so notes can never be forgotten.

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

source Packaging/release.env          # brings in SU_FEED_URL / RELEASE_REPO
"$BIN/generate_appcast" \
  --download-url-prefix "$(dirname "$SU_FEED_URL")/updates/" \
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
