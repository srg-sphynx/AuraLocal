# Changelog

All notable changes to Aura Local are documented here. Version numbers follow the app's `CFBundleShortVersionString`.

## [Unreleased]

## [3.3.2] — 2026-07-03

### Fixed
- **The version number shown in the app is now correct.** The About footer had a hardcoded "v3.2" that never tracked releases. The app now reads its version from the bundle (`CFBundleShortVersionString`) everywhere it's shown, so it can never go stale again — Settings → About and Settings → Software Updates both display the real running version and build.

### Added
- **"What's New" in the app.** A new changelog viewer (Settings → Software Updates → *What's New*, and Settings → About) shows the release notes for your current version, with a one-tap expand to the full history. It also pops up **once, automatically, the first time you open the app after an update** — so you always know what changed. Content is the bundled `CHANGELOG.md`, the same notes published on each GitHub Release.
- Every GitHub Release now carries the detailed, per-version changelog as its release notes (previously just a pointer). The release tooling refuses to publish a version that has no `CHANGELOG.md` entry, so notes can never be forgotten.

## [3.3.1] — 2026-07-03

### Changed
- **Theme switching no longer resets your scroll position.** 3.3.0 recolored the window by rebuilding the whole view tree (`.id`), which snapped Settings — and any open chat — back to the top on every theme change. The palette is now exposed as *dynamic* colors that resolve light/dark by the drawing appearance, so switching Mode (or the system flipping in *System* mode) recolors the entire window **instantly and in place**, with nothing rebuilt and no scroll lost. Accent, high-contrast, and transparency changes likewise re-render in place.
- **Transparency is now a set of presets, not a slider.** The continuous slider is gone; pick **Solid / Subtle / Medium / Heavy** with one tap. Every glass panel re-tints live.

### Fixed
- Confirmed light↔dark flips every section in one pass (no more "hover to reveal the right color") — including panes whose parent view doesn't observe the theme, since the dynamic colors re-resolve at the layer level regardless.

## [3.3.0] — 2026-07-03

### Added
- **Open sources straight from the chat.** Every source chip under an answer is now clickable — click it to open the exact file that grounded the response in its default app (Preview for PDFs, your editor for Markdown, etc.). Right-click for **Reveal in Finder**.
- **“Sources in this chat” panel.** The Context inspector now lists every unique source cited across the whole conversation — highest-relevance first — so you can jump back to the material behind any earlier answer, not just the most recent turn. Each row opens the file on click. Source rows and chips show a per-format icon (PDF / doc / sheet / web / book).

### Fixed
- **Light/Dark now switches cleanly and globally.** Changing the appearance Mode (or the system flipping in *System* mode) previously left text in some sections the wrong color until you hovered over it. The theme now re-colors the whole window in one pass on any structural change, with no stale text.
- **Mode works while a custom theme is active.** Applying a saved theme no longer locks the light/dark base — the Mode switch stays the source of truth, and a custom theme only layers its accent (and matching-base surface tweaks) on top. Applying a preset also snaps Mode to the base it was saved with.
- **Light-mode contrast.** Accent-derived text now stays readable (WCAG AA) for *any* accent — bright emerald/amber/cyan accents were previously ~3:1 against the near-white surface. Success and warning colors were darkened in light mode for the same reason.
- **Transparency stays smooth.** Dragging the Transparency slider re-tints every glass panel live (not just the ones on screen) without rebuilding the view tree, so scroll positions are preserved.

## [3.2.0] — 2026-07-02

### Added
- **Automatic updates** — built-in over-the-air updating via [Sparkle](https://sparkle-project.org). The app checks an appcast in the background and installs signed (EdDSA) releases with the standard update UI. New **Software Updates** section in Settings plus a **Check for Updates…** menu item. See [docs/UPDATES.md](docs/UPDATES.md) for the publishing workflow.

### Fixed
- **Enter to send** — the composer is now backed by an AppKit text view: **Return sends** the message and **⇧Return / ⌥Return inserts a new line**. Previously the `TextEditor`'s `.onSubmit` never fired, so sending required clicking the button.
- **Appearance changes no longer scroll the page to the top.** Theme edits (transparency, accent, high contrast, density) previously rebuilt the entire view tree via `.id()`, resetting Settings to the top on every tweak. Re-theming now flows through observation and re-renders in place, preserving scroll and other transient state.
- **High contrast now makes a visible difference** — stronger panel borders, outlines, and field/card fills in both light and dark high-contrast modes.
- **Sidebar Documentation / GitHub links now open.** They were decorative (no action); they now open the user guide and repository in your browser.

## [3.1.0] — 2026-07-02

### Changed
- Panes now run to the window top; the sidebar header clears the traffic lights.
- Rebuilt the light palette on white-based fills with stronger borders for better contrast.
- Text size now follows the macOS system setting and re-resolves when the app becomes active (the in-app text-size slider was replaced by a glass-transparency slider).
- Model discovery publishes a single diffed refresh, so background polling (~5s, quiet) no longer re-renders the app.

### Added
- **Offline model detection** — installed Ollama models are detected by reading on-disk manifests when the server is stopped.
- **Glass transparency** control in Appearance.
- Live active-node status indicator (none / offline / missing / ready / loaded).
- Real runtime memory history in the Model Zoo chart.
- Immediate refresh after any Ollama control action (pull / load / unload / server start-stop).

### Fixed
- Various performance issues: lighter status-dot animation, plain-text rendering while streaming, local composer draft state, and a correctly wired ⌘↩ send shortcut.

## [3.0.0] — 2026-07-01

### Added
- **Multi-format ingestion** — PDF (with optional OCR), DOCX, EPUB, RTF/RTFD, HTML, MediaWiki, and CSV/TSV, all normalized to Markdown (adds SwiftSoup and ZIPFoundation).
- **Retrieval upgrades** — contextual chunk enrichment, Reciprocal Rank Fusion re-ranking, parent-document expansion, optional LLM-judge rerank, query expansion (Multi-Query / HyDE), and an optional IVF approximate-nearest-neighbor index.
- **Diagnostics** — a filterable log console, per-file issues list, and export.
- **Onboarding** — a live five-step guided setup flow.
- Database schema v4 with performance PRAGMAs.

### Changed
- Theming and contrast fixes, including WCAG contrast helpers and adaptive color tokens to address light-mode wash-out.

## [2.0.0] — 2026-07-01

### Changed
- **Full-embed indexing** — always runs the embedding pass; the query embeds only at retrieval time. The pass is resumable and auto-resumes when the embedding model is ready.
- Vectors stored as Float16 blobs (schema v3), halving RAM and disk with cosine similarity effectively lossless.
- Hybrid retrieval — a union of BM25 keyword and pure-semantic candidates, re-ranked and filtered.

### Added
- Ollama control (start/stop server, pull/update/stop models) surfaced in the Model Zoo.
- Danger Zone with "clear index and chats" and "factory reset".
