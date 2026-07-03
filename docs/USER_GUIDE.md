# User Guide

A tour of every screen in Aura Local and the settings that matter. Screens are shown in the [screenshots](screenshots/) folder and embedded below.

## First run: onboarding

On first launch, Aura Local shows a five-step guided setup that reflects live system state as you go:

1. Confirm your provider (Ollama, LM Studio, or both) is running.
2. Pick a chat model.
3. Pick an embedding model (`bge-m3` via Ollama is the recommended default).
4. Add your first knowledge base folder.
5. Kick off the initial index.

You can replay onboarding at any time from **Settings**.

## Chat

![Chat interface](screenshots/chat-interface.png)

The chat view is where you talk to your documents. Each answer is grounded in passages retrieved from your knowledge base, and the sources are shown alongside the response so you can verify where an answer came from.

- **History-aware retrieval** keeps follow-up questions on topic — the last few turns are folded into the retrieval query, so "what about the second one?" still resolves correctly.
- **Adaptive sourcing** keeps the conversation fast. When you first ask about something, Aura may pull a few dozen sources from a large vault; it remembers that working set, so a follow-up on the same material is answered near-instantly without re-searching everything. Ask about a *different* file — even one that wasn't in that first batch — and Aura automatically searches the whole vault again and brings the right sources in. See [Retrieval tuning](#retrieval-tuning) to adjust it.
- Streaming responses render as plain text while generating and switch to full Markdown once complete, keeping the UI smooth.
- Press **⌘↩** to send.

### Relevant files & opening sources

Every answer lists the sources behind it as a **Relevant files** strip beneath the response — one chip per file, most-relevant first, with a relevance percentage.

- Once the answer finishes, the files it **actually referenced** are highlighted and moved to the front, and the strip notes how many were cited — so you can tell at a glance which sources the response leaned on versus which were merely available.
- **Click a source chip** to open that exact file in its default app — Preview for a PDF, your editor for Markdown, and so on. **Right-click** a chip for **Reveal in Finder**.
- Open the **Context inspector** (the toggle at the top-right of the chat) to see **Sources in this chat** — every unique file cited across the whole conversation, most-relevant first. Each row opens the file on click, so you can get back to the material behind any earlier answer, not just the last one.

If a source no longer opens, the file was likely moved or renamed after it was indexed; re-index the vault to refresh its location.

## Knowledge base

![Knowledge base](screenshots/knowledge-base.png)

A knowledge base is a folder of documents you have added. From here you can:

- Add or remove folders.
- See what is indexed and the status of each source.
- Review supported formats — Markdown/Obsidian, PDF, DOCX, EPUB, RTF/RTFD, HTML, MediaWiki, CSV/TSV, and plain text. Code files are supported but off by default.

Aura Local uses security-scoped bookmarks to retain access to your folders across launches, and a vault watcher keeps the index in sync as files change.

## Indexing

![Indexing](screenshots/indexing.png)

The indexing view shows extraction and embedding progress.

- **Extraction** normalizes every file to Markdown and chunks it along headings.
- **Embedding** turns chunks into on-device vectors. This pass is **resumable** — if it is interrupted, or if the embedding model was not ready, it picks up automatically once the model becomes available.
- The first pass over a very large vault is a one-time job. It runs off the main thread, but it is substantial; let it finish in the background.

## Model Zoo

![Model Zoo](screenshots/model-zoo.png)

The Model Zoo is your model control center. It discovers models available to your providers and shows their status. A memory chart tracks real runtime memory usage.

Even when the Ollama server is stopped, installed models are still detected by reading Ollama's on-disk manifests, so the list stays accurate.

### Ollama control

![Ollama control](screenshots/ollama-control.png)

![Model Zoo CLI control](screenshots/model-zoo-cli-control.png)

The Ollama Control card drives the Ollama CLI directly from the app:

- Start / stop the Ollama server
- Pull, update, load, and unload models
- View running models

Every action has a copyable command in the cheatsheet, so you can run it yourself in a terminal if you prefer. State changes trigger an immediate refresh, so the UI reflects reality without waiting for the next poll.

### Model settings

![Model settings](screenshots/model-settings.png)

Choose which model handles chat and which handles embeddings, and switch providers per role. The recommended default is LM Studio for chat and Ollama `bge-m3` for embeddings, but any combination works.

## Diagnostics

![Diagnostics](screenshots/diagnostics.png)

The Diagnostics view is a filterable log console plus a per-file Issues list. If a document failed to extract cleanly, it appears here with the reason rather than silently breaking the index. Use **Export** to save logs when reporting a bug.

## Settings

![Settings](screenshots/settings.png)

![Settings — models](screenshots/settings-models.png)

Settings covers providers and models, retrieval tuning, appearance, onboarding replay, an **On-Disk Footprint** panel, and a **Danger Zone**.

**On-Disk Footprint** shows exactly what Aura keeps on disk — vector index, fast-search cache, chats, and settings — with a running total. Everything lives in a single folder; nothing is scattered across your system, and no scratch files are left behind by document parsing. **Reclaim disk space** compacts the store and reports how much it freed; it's non-destructive (all vectors and chats are kept). Removing a vault erases its vectors automatically, and deleting a chat frees its cached sources.

The **Danger Zone** offers two destructive, confirmation-gated actions:

- **Clear index and chats** — wipes the database, chats, and vault list but keeps your settings.
- **Factory reset** — additionally erases all data files and resets settings to defaults, leaving nothing behind.

### Retrieval tuning

From the inspector and settings you can adjust:

- **Retrieval top-K** — how many passages are returned to the model.
- **Candidate file window** and **minimum similarity** — how candidates are gathered and filtered.
- **Re-rank mode** — off (semantic only), hybrid RRF (default; fuses keyword + semantic ranks), or LLM-judge. Source chips show the semantic relevance as a percentage; the ordering reflects the fusion.
- **Query expansion** — off, Multi-Query, or HyDE.
- **Parent-document expansion** — include neighboring passages for more context.
- **ANN index** — enable the approximate index for very large collections (off by default; exact scan is the default path).
- **Adaptive source cache** — on by default. Keeps a per-chat map of the sources already retrieved so in-topic follow-ups skip a full vault re-scan. The **Reuse threshold** controls how close a follow-up must be to the cached sources before Aura reuses them: raise it to re-search more often (fresher, thorough), lower it to reuse more aggressively (faster). Questions about new material always search the whole vault regardless.

## Appearance and theming

![Theme engine](screenshots/theme-engine.png)

![Custom themes](screenshots/custom-themes.png)

Aura Local ships a full theming engine:

- Light, dark, or system-following themes
- Accent color — any accent stays readable (the app keeps accent-derived text at WCAG AA against the background), so bright accents don't wash out in light mode
- High-contrast mode
- Density control
- **Glass transparency** for the translucent panes — pick a level (Solid / Subtle / Medium / Heavy) and every panel re-tints live
- Custom presets you can save and switch between

**Mode** (Light / Dark / System) always controls the light/dark base. A custom preset layers its accent on top and, when you apply it, snaps the Mode to the base it was saved with — so you can keep switching Light/Dark afterward. Switching Mode re-colors the entire window at once — instantly and in place, so you never lose your scroll position.

Text size follows your macOS system text-size setting automatically and updates when you change it.

## Tips

- If model status looks stale, any Ollama control action forces an immediate refresh.
- Keep a single, current install of Aura Local. An older copy left in `/Applications` can overwrite settings with an outdated schema (see [Known Issues](../README.md#known-issues)).
- When reporting a bug, export logs from Diagnostics and include your macOS version, app version, and provider/model setup.
