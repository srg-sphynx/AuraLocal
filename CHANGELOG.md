# Changelog

All notable changes to Aura Local are documented here. Version numbers follow the app's `CFBundleShortVersionString`.

## [Unreleased]

## [4.0.2] — 2026-09-06

A licensing and release-hardening update. **There are no functional changes** — indexing, retrieval, chat, theming, and every setting behave exactly as they did in 4.0.1. Your vaults, chats, and settings are untouched.

### Changed
- **Aura Local is now source-available under a proprietary license rather than MIT.** The app is still free to download and use, and the complete source stays public so you can read it and verify for yourself that nothing leaves your Mac. What changed is what *others* may do with that source: redistributing it, publishing a fork, shipping a derivative or rebranded app, and commercial use now require written permission. The bundled open-source components (SwiftSoup, ZIPFoundation, Sparkle) keep their own MIT licenses and are unaffected. See [LICENSE](LICENSE) for the full terms.
- **Every source file now carries an explicit copyright notice.**

### Security
- **The auto-update channel is no longer described in public source.** The update feed address and its signing key used to be committed to the repository. They are now supplied at packaging time from a local configuration file that is never published, so a copy of Aura Local built from a clone of the repository ships with auto-update switched off and cannot poll — or impersonate — the official update feed. Update verification itself is unchanged: releases are still EdDSA-signed and checked before installation.

### Notes
- Aura Local remains free to use. This change supports developing it into a sustained, properly supported product rather than leaving it unlicensed for anyone to resell.

## [4.0.1] — 2026-07-03

A storage-hygiene release: Aura now cleans up after itself and shows you exactly what it keeps on disk.

### Fixed
- **Removing a vault now reclaims its space.** Previously, deleting a vault forgot it from the list but left *all of its embeddings and keyword index behind* in the store — orphaned data that quietly took up disk forever. Removing a vault now erases its vectors, keyword rows, and fast-search sidecar, then compacts the database to give the space back. (The heavy work runs in the background, so removing a large vault doesn't freeze the app.)
- **Deleting a chat frees everything tied to it.** A deleted conversation now also drops its cached "working set" of sources from memory, so nothing lingers.

### Added
- **On-Disk Footprint (Settings).** A new panel shows precisely what Aura stores and where — vector index, fast-search cache, chats, settings — with a running total. Everything lives in a single folder; nothing is scattered across your system.
- **Reclaim disk space.** One button compacts the store and reports how much it freed. It's non-destructive — every vector and chat is kept; it only releases space left over from deletions.

### Notes
- Aura writes nothing outside its own data folder apart from the initial vault index and its regenerable speed caches. Documents are parsed in memory (no temp files extracted to disk), and logs stay in memory. Factory reset now leaves nothing behind.

## [4.0.0] — 2026-07-03

Aura Local 4.0 is about **adaptive retrieval** — the app now maps the sources each conversation is working with, so answers are both faster and more clearly grounded.

### Added
- **Relevant files, per answer.** Every reply now surfaces the exact files behind *that* answer as a "Relevant files" strip — deduplicated to one chip per source (no more the same note three times), highest-relevance first, each click-to-open. Once the reply finishes, the files the answer actually referenced are **highlighted and floated to the front** and the strip shows how many were cited, so you can see at a glance which sources the response leaned on.
- **Adaptive source cache — fast follow-ups, smart re-sourcing.** When a chat first pulls, say, 50 sources for a question, Aura keeps that working set in memory. A follow-up that lives inside those same sources is answered **without re-scanning the whole vault** — it's ranked straight off the cached material, so it's near-instant. Ask about something *outside* the working set and Aura automatically searches the entire vault again, finds the right files, and folds them into the chat's map. The result: quick in-topic follow-ups, without ever getting "stuck" on the first batch of sources. Tunable in the Context inspector and Settings (**Adaptive source cache** + **Reuse threshold**); the inspector shows how many sources are currently mapped for the chat.

### Changed
- **Hybrid re-rank now shows a relevance you can trust.** Under the default Hybrid (RRF) re-ranker, source chips previously displayed the raw fusion score — a tiny number that always read as "2–3%". Chips now show the **semantic similarity (0–100%)** as the relevance, while the ordering still comes from the keyword + semantic rank fusion. The number finally matches what you'd expect.

### Fixed
- **Hybrid search no longer drops strong keyword matches.** A passage that's an exact term match but a weak vector match could be filtered out by the Minimum Similarity floor *before* the keyword + semantic fusion ever saw it — quietly defeating the point of hybrid retrieval. Keyword matches are now always kept in the fusion, so a perfectly on-topic term match can't be silently discarded.

## [3.3.3] — 2026-07-03

### Fixed
- **The first message after indexing a new vault no longer appears to do nothing.** Previously, the assistant reply bubble was only created *after* retrieval finished. On the very first query against a freshly-indexed vault — when the embedding model is still cold or busy finishing the bulk embedding pass — that retrieval was slow, so the message looked like it was silently dropped (it worked on the second try once the model had warmed up). Aura now shows the **"Thinking…"** reply bubble the instant you hit send, before retrieval starts, so there's always immediate feedback.
- **Retrieval can no longer stall the whole answer.** The query embedding is now bounded by a timeout — if the embedding server is cold or saturated and doesn't respond in time, retrieval degrades gracefully to keyword search instead of hanging.
- **Streamed replies always land in the right conversation.** Starting a new chat while a reply was still generating could send tokens into the wrong session (new chats are inserted at the top, which shifted the position the stream was writing to). The stream now targets the reply by identity, so it can't cross wires.

### Changed
- **Clearer retrieval controls.** The Context inspector and Settings now label the two most-asked-about knobs plainly: **"Max Sources (Top-K)"** — the most passages fed to the model per answer — and **"Smart Scan Window"** — how many top keyword-matching files are pulled in as candidates before ranking. Both now carry a one-line explanation of what they do and the speed/recall trade-off.

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
