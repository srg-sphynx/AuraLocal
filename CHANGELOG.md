# Changelog

All notable changes to Aura Local are documented here. Version numbers follow the app's `CFBundleShortVersionString`.

## [Unreleased]

- **Automatic updates** — built-in auto-updating so new versions install without a manual download.

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
