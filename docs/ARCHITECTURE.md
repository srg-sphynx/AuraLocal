# Architecture

This document describes how Aura Local is built: the ingestion pipeline, the retrieval stack, on-disk storage, model management, diagnostics, and the theming system. It reflects the current release (3.2.0).

Aura Local is a native macOS app written in Swift and SwiftUI (Swift tools 5.9, macOS 14+). It is distributed as a Swift Package Manager executable target and is intentionally **non-sandboxed** so it can shell out to the Ollama CLI and read local files and Ollama's on-disk model store.

## Dependencies

The app keeps its dependency surface small:

| Dependency | Purpose |
| --- | --- |
| `CSQLite` (system library shim) | Direct SQLite access, including FTS5 |
| [SwiftSoup](https://github.com/scinfu/SwiftSoup) | HTML → structured text (pure-Swift jsoup port) |
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | Reading DOCX and EPUB containers (both are ZIP archives) |
| PDFKit / Vision (system) | PDF text extraction and optional OCR |

## Source layout

```
Sources/AuraLocal/
├─ App/            App entry, root view, environment wiring
├─ Models/         Domain models and AppSettings
├─ Theme/          ThemeManager, palette tokens, glass components
├─ Services/
│  ├─ FileSystem/  Project store, security-scoped bookmarks, vault watcher
│  ├─ RAG/         Ingestion, chunking, embeddings, vector index, retrieval
│  │  └─ Extractors/  Per-format document extractors
│  ├─ Persistence/ SQLite database, app paths, settings store
│  ├─ Inference/   Ollama & LM Studio providers, model advisor, Ollama control
│  ├─ Diagnostics/ Logging, log store, typed errors, toasts
│  └─ Telemetry/   Runtime telemetry snapshots
└─ Features/       SwiftUI feature modules (Chat, Sidebar, Settings,
                   ModelZoo, KnowledgeBase, Diagnostics, Indexing,
                   Onboarding, Inspector, Shared)
```

## Ingestion pipeline

The goal of ingestion is to reduce every supported format to a single common representation — Markdown — so that one heading-aware chunker handles all content uniformly.

- **Supported formats** are declared in one place, `Services/RAG/SupportedFormats.swift`, which maps file extensions to a `FileCategory`. The default included-extensions set, the file ingestor, and the vault watcher's ignore logic all read from this single source of truth.
- **`DocumentExtractor`** dispatches each file to a format-specific extractor and returns normalized Markdown plus any warnings. `IndexingService.indexOneFile` runs everything through this path.

Extractors in `Services/RAG/Extractors/`:

| Format | Extractor / approach |
| --- | --- |
| HTML, EPUB content, wiki HTML | `HTMLToMarkdown` via SwiftSoup |
| DOCX | `XMLParser` over `word/document.xml` (ZIP container) |
| EPUB | OPF spine traversal |
| RTF / RTFD | `NSAttributedString` |
| CSV / TSV | Quote-aware parser → Markdown table |
| MediaWiki | `WikiExtractor` |
| PDF | `PDFExtractor` — page markers, optional Vision OCR fallback |

Extractors are **best-effort**: they never throw into the indexing loop. Failures are captured as warnings and surfaced per-file in Diagnostics rather than aborting the pass. Code files are supported but disabled by default.

**Chunking.** `MarkdownChunker` splits normalized Markdown along headings. Each chunk is contextually enriched — the document title and tags are prepended to the text that gets embedded (`chunk(docContext:)`) — so a passage carries enough context to be retrieved on its own.

**Format upgrades.** When new formats are added in an update, a one-time migration (`SettingsStore.migrate`, guarded by an upgrade flag) merges the new extensions into any existing user configuration so previously indexed vaults pick them up.

## Storage

Persistence lives in `Services/Persistence/AppDatabase.swift`, an SQLite database at schema `user_version = 4`.

- **Vectors are stored as Float16 blobs**, halving RAM and disk versus Float32 with cosine similarity remaining effectively lossless. Encoding/decoding is handled by `VectorMath` (decode uses `loadUnaligned`).
- **Full-text search** uses an FTS5 table (`chunks_fts`) with BM25 ranking.
- **Schema v4 additions** (additive `ALTER TABLE`): `files.error_message`, `files.title`, and `chunks.bucket` (with an index) for the ANN index.
- **Performance PRAGMAs**: enlarged cache, memory-mapped I/O, and in-memory temp store.
- A streaming cosine scan (`semanticTopK`) computes similarity in O(k) memory rather than materializing all vectors.

## Retrieval

Retrieval is orchestrated by `IndexingService.retrieve` and is configurable from the inspector and settings.

1. **Candidate generation** — a hybrid union of BM25 keyword candidates and pure-semantic top-K candidates. The semantic scan runs off the main thread.
2. **Re-ranking** — Reciprocal Rank Fusion (RRF) fuses the keyword and semantic rankings. The mode is selectable (`off` / `hybridRRF` / `llmJudge`); an optional LLM-judge rerank is available.
3. **Parent-document expansion** — when enabled, adjacent-ordinal chunks are merged in (`AppDatabase.neighborChunks`) so the model sees surrounding context, not just an isolated snippet.
4. **Filtering** — a minimum-similarity threshold and a final top-K cut (`retrievalTopK`) trim the result set.
5. **Query expansion** — optionally rewrite the query before retrieval (`off` / `multiQuery` / `hyde`) via a one-shot completion helper.

**History-aware retrieval.** `ChatViewModel` folds the last few user turns into the retrieval query so follow-up questions keep their referent.

### Approximate-nearest-neighbor index (optional)

For very large collections, `Services/RAG/VectorIndex.swift` provides an **IVF** index (coarse quantization with spherical k-means centroids) rather than HNSW — HNSW's memory footprint on very large vaults is prohibitive, whereas IVF keeps only the centroids in RAM and stores a per-chunk bucket column in SQLite. The index is built after embedding passes once the collection is large enough and has grown sufficiently, stored as a sidecar file per project. Queries probe the nearest buckets; a special bucket is always probed so newly added chunks are never missed.

The ANN index is **opt-in**. Exact semantic scan is the default and is the verified fallback.

## Embedding lifecycle

The embedding pass is **resumable**. `IndexingService` observes the embedding model's readiness and automatically resumes embedding for all pending chunks when the model becomes available, so an interrupted or deferred pass continues on its own once the provider is ready.

## Model management and providers

`Services/Inference/` contains provider abstractions for **Ollama** and **LM Studio** behind a common interface, plus:

- **`InferenceManager`** — discovers online providers and available models, auto-picks sensible defaults (LM Studio for chat, Ollama `bge-m3` for embeddings), tracks embedding status, and publishes a single diffed refresh so background polling (every ~5s, quiet) does not re-render the UI. It exposes an active-node state (`none` / `offline` / `missing` / `ready` / `loaded`) that drives the status indicator.
- **Offline model detection** — when the Ollama server is not running, model discovery falls back to reading Ollama's on-disk manifests directly (`~/.ollama/models/manifests/...`), so installed models are still listed even though `ollama list` would require the server.
- **`OllamaControlService`** — shells out to the `ollama` CLI (possible because the app is non-sandboxed) to start/stop the server, pull/update/stop models, and query running models. State changes trigger an immediate refresh. Commands are surfaced in the Model Zoo's Ollama Control card with a copyable cheatsheet.
- **`ModelAdvisor`** — a curated, offline model table used by the auto-configure flow.

## Diagnostics

`Services/Diagnostics/` implements logging that cannot itself cause UI jitter:

- **`Log`** is an `os.Logger` facade that also mirrors into a thread-safe ring buffer (`LogStore`), fully decoupled from SwiftUI — the UI polls it and it never hops to the main thread.
- **`ToastCenter`** provides non-blocking toast notifications, rendered as an overlay from the root view.
- The **Diagnostics** feature is a filterable log console plus a per-file Issues list and one-click export.

## Theming and the app shell

The theming system (`Theme/ThemeManager.swift`, `Theme/Theme.swift`) exposes static palette tokens (`Theme.Palette.*`) that read from a mirrored palette, so a large number of call sites stay unchanged while becoming fully dynamic. The root view applies the selected theme and re-renders on theme revision changes for live switching.

Supported controls: light / dark / system, accent color, high-contrast mode, density, and custom presets. A **glass transparency** slider drives the tint of the app's translucent panes. Text size follows the macOS system setting (re-resolved when the app becomes active) rather than an in-app slider. Applying an unchanged theme is a no-op, so window re-activation is free. WCAG contrast helpers (with a debug-only audit) guard against low-contrast palettes.

## Notes and limitations

- The extractors are exercised in the running app but do not yet have a standalone automated test suite (a small library refactor would be needed to make them independently testable). Unusual documents may extract imperfectly.
- The IVF ANN index is the newest subsystem and is opt-in; the exact scan remains the trusted default.

See [Known Issues](../README.md#known-issues) for the user-facing summary.
