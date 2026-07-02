# Building from source

## Prerequisites

- macOS 14 (Sonoma) or later
- Xcode 15+ (or a matching Swift toolchain) with Swift tools 5.9+
- Command Line Tools installed (`xcode-select --install`)

The project is a Swift Package Manager executable — there is no `.xcodeproj`. Dependencies (SwiftSoup, ZIPFoundation) are resolved automatically by SPM.

## Clone and build

```bash
git clone https://github.com/srg-sphynx/AuraLocal.git
cd AuraLocal
swift build -c release
```

The compiled binary lands in `.build/release/AuraLocal`. Because the app relies on a bundle (icon, `Info.plist`, entitlements), run it as a packaged `.app` rather than invoking the raw binary directly — see below.

To iterate during development:

```bash
swift build          # debug build
```

## Producing a signed .app and .dmg

The packaging script builds a release binary, generates the app icon, assembles the `.app` bundle, ad-hoc code signs it (with entitlements), and creates a distributable `.dmg`:

```bash
./Packaging/build_app.sh
```

By default the artifacts are written to a `Builds/` directory alongside the repository:

- `Builds/Aura Local.app` — the ready-to-run app bundle
- `Builds/AuraLocal-v<version>.dmg` — the distributable disk image

You can pass a custom output directory as the first argument:

```bash
./Packaging/build_app.sh /path/to/output
```

The script reads the version from `Packaging/Info.plist` (`CFBundleShortVersionString`).

## Packaging contents

```
Packaging/
├─ Info.plist              App metadata and version
├─ AuraLocal.entitlements  Entitlements (non-sandboxed)
├─ build_app.sh            Build → sign → DMG pipeline
└─ generate_icon.swift     Programmatic app-icon generation
```

## Signing and notarization

The current pipeline uses **ad-hoc signing** (`codesign --sign -`). This is enough to run locally but is **not notarized**, so macOS Gatekeeper will warn on first launch on other machines. To ship notarized builds you would:

1. Sign with a Developer ID Application certificate instead of ad-hoc.
2. Submit the `.dmg` to Apple's notary service (`xcrun notarytool submit`).
3. Staple the ticket (`xcrun stapler staple`).

Notarized release builds are on the [roadmap](../README.md#roadmap).

## Cutting a release

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Packaging/Info.plist`.
2. Update [`CHANGELOG.md`](../CHANGELOG.md).
3. Run `./Packaging/build_app.sh`.
4. Create a GitHub Release and attach the generated `.dmg`.

Build artifacts (`.build/`, `.dist/`, `.dmg`, `.app`) are gitignored — releases are published through GitHub Releases, not committed to the repository.
