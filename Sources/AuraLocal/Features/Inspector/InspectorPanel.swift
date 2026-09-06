//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import SwiftUI

/// Right-side collapsible panel. Shows live retrieval context, indexed files in
/// the active vault with chunking status, and vector-DB statistics.
struct InspectorPanel: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var chat: ChatViewModel
    @EnvironmentObject var projects: ProjectStore
    @EnvironmentObject var indexing: IndexingService
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var theme: ThemeManager   // re-render in place on theme change

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.glassBorderSoft)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    EmbeddingStatusBanner(compact: true)
                    if let note = indexing.retrievalNote, !note.isEmpty {
                        Text(note).font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.outline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    retrievalDirectives
                    chatSourcesSection
                    retrievalParams
                    if !chat.lastRetrieval.isEmpty { retrievedContext }
                    indexedFilesSection
                }
                .padding(14)
            }
            Divider().overlay(Theme.glassBorderSoft)
            vectorStats
        }
        .glassPane(material: .sidebar)
    }

    private var header: some View {
        HStack {
            Text("Context").font(Theme.Font.titleSm()).foregroundStyle(Theme.Palette.onSurface)
            Spacer()
            Button { env.inspectorVisible = false } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.Palette.outline)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
    }

    // MARK: Retrieval directives (which vault)

    private var retrievalDirectives: some View {
        VStack(alignment: .leading, spacing: 8) {
            MicroLabel(text: "Retrieval Directives")
            if projects.projects.isEmpty {
                Text("No vaults indexed.").font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.outline)
            } else {
                ForEach(projects.projects) { p in
                    HStack(spacing: 8) {
                        Image(systemName: "circle.hexagongrid.fill").font(.system(size: 11))
                            .foregroundStyle(projects.selectedProjectID == p.id ? Theme.Palette.primary : Theme.Palette.outline)
                        Text(p.name).font(Theme.Font.bodySm())
                            .foregroundStyle(Theme.Palette.onSurfaceVariant).lineLimit(1)
                        Spacer()
                        if projects.selectedProjectID == p.id {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 11))
                                .foregroundStyle(Theme.Palette.primary)
                        }
                    }
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .glassCard(radius: Theme.Radius.sm, selected: projects.selectedProjectID == p.id)
                    .contentShape(Rectangle())
                    .onTapGesture { projects.selectedProjectID = p.id }
                }
            }
        }
    }

    // MARK: Retrieval params

    private var retrievalParams: some View {
        VStack(alignment: .leading, spacing: 12) {
            sliderRow(title: "Max Sources (Top-K)",
                      value: Binding(get: { Double(settingsStore.settings.retrievalTopK) },
                                     set: { settingsStore.settings.retrievalTopK = Int($0) }),
                      range: 1...50, step: 1,
                      label: "\(settingsStore.settings.retrievalTopK)",
                      caption: "Most passages fed to the model per answer. Higher = more sources cited, more context.")
            sliderRow(title: "Smart Scan Window",
                      value: Binding(get: { Double(settingsStore.settings.candidateFileWindow) },
                                     set: { settingsStore.settings.candidateFileWindow = Int($0) }),
                      range: 5...200, step: 5,
                      label: "\(settingsStore.settings.candidateFileWindow)",
                      caption: "How many top keyword-matching files are pulled in as candidates before ranking. Wider = more thorough recall, slightly slower.")
            sliderRow(title: "Min Similarity",
                      value: $settingsStore.settings.minSimilarity,
                      range: 0...1, step: 0.01,
                      label: String(format: "%.2f", settingsStore.settings.minSimilarity))
            Toggle(isOn: Binding(
                get: { settingsStore.settings.rerankMode != .off },
                set: { settingsStore.settings.rerankMode = $0 ? .hybridRRF : .off })) {
                Text("Re-rank with hybrid score").font(Theme.Font.bodySm())
                    .foregroundStyle(Theme.Palette.onSurfaceVariant)
            }
            .toggleStyle(.switch).controlSize(.mini).tint(Theme.Palette.primaryVivid)

            adaptiveCacheControls
        }
    }

    // MARK: Adaptive source cache (fast follow-ups within a chat's sources)

    @ViewBuilder
    private var adaptiveCacheControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $settingsStore.settings.adaptiveSourceCache) {
                Text("Adaptive source cache").font(Theme.Font.bodySm())
                    .foregroundStyle(Theme.Palette.onSurfaceVariant)
            }
            .toggleStyle(.switch).controlSize(.mini).tint(Theme.Palette.primaryVivid)
            Text("Answer follow-ups from the sources already open in this chat, without re-scanning the whole vault. New topics still trigger a fresh search.")
                .font(Theme.Font.micro()).foregroundStyle(Theme.Palette.outline)
                .fixedSize(horizontal: false, vertical: true)
            if settingsStore.settings.adaptiveSourceCache {
                sliderRow(title: "Reuse Threshold",
                          value: $settingsStore.settings.adaptiveReuseThreshold,
                          range: 0.4...0.9, step: 0.01,
                          label: String(format: "%.2f", settingsStore.settings.adaptiveReuseThreshold),
                          caption: "How close a follow-up must be to the cached sources to skip a full re-scan. Higher = re-scans more often (fresher), lower = reuses more (faster).")
                if let sid = chat.currentSessionID {
                    let n = indexing.cachedSourceCount(session: sid)
                    if n > 0 {
                        Label("\(n) sources mapped for this chat", systemImage: "bolt.horizontal.circle")
                            .font(Theme.Font.micro()).foregroundStyle(Theme.Palette.primary)
                    }
                }
            }
        }
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>,
                           step: Double, label: String, caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
                Spacer()
                Text(label).font(Theme.Font.bodySm().monospacedDigit()).foregroundStyle(Theme.Palette.primary)
            }
            Slider(value: value, in: range, step: step).controlSize(.mini).tint(Theme.Palette.primaryVivid)
            if let caption {
                Text(caption).font(Theme.Font.micro()).foregroundStyle(Theme.Palette.outline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Sources in this chat (every cited file, clickable — opens the exact file)

    /// Unique cited files across the whole session, highest-scoring first, so the
    /// user can jump back to the sources behind any earlier answer — not just the
    /// last turn (that's `retrievedContext`).
    private var sessionSources: [Citation] {
        guard let msgs = chat.currentSession?.messages else { return [] }
        var seen = Set<String>()
        var out: [Citation] = []
        for m in msgs where m.role == .assistant {
            for c in m.citations {
                let key = "\(c.projectID?.uuidString ?? "-")|\(c.filePath)"
                if seen.insert(key).inserted { out.append(c) }
            }
        }
        return out.sorted { $0.score > $1.score }
    }

    @ViewBuilder
    private var chatSourcesSection: some View {
        let sources = sessionSources
        if !sources.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    MicroLabel(text: "Sources in this chat")
                    Spacer()
                    Text("\(sources.count)").font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.outline)
                }
                ForEach(sources) { SourceRow(citation: $0) }
                Text("Click a source to open the exact file.")
                    .font(Theme.Font.micro()).foregroundStyle(Theme.Palette.outline)
            }
        }
    }

    // MARK: Retrieved context preview (what fed the last answer)

    private var retrievedContext: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                MicroLabel(text: "Retrieved Context")
                Spacer()
                Text("\(chat.lastRetrieval.count) chunks").font(Theme.Font.bodySm())
                    .foregroundStyle(Theme.Palette.outline)
            }
            ForEach(chat.lastRetrieval) { c in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(c.fileName).font(Theme.Font.bodySm().weight(.semibold))
                            .foregroundStyle(Theme.Palette.onSurface).lineLimit(1)
                        Spacer()
                        Text(String(format: "%.0f%%", c.score * 100))
                            .font(Theme.Font.bodySm().monospacedDigit()).foregroundStyle(Theme.Palette.success)
                    }
                    if let h = c.heading {
                        Text(h).font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.primary).lineLimit(1)
                    }
                    if !c.tags.isEmpty {
                        Text(c.tags.prefix(4).map { "#\($0)" }.joined(separator: " "))
                            .font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.outline).lineLimit(1)
                    }
                }
                .padding(9)
                .glassCard(radius: Theme.Radius.sm)
            }
        }
    }

    // MARK: Indexed files + chunking status

    private var indexedFilesSection: some View {
        let files = projects.selectedProjectID.flatMap { indexing.indexedFiles[$0] } ?? []
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                MicroLabel(text: "Indexed Files")
                Spacer()
                Text("\(files.count)").font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.outline)
            }
            if files.isEmpty {
                Text("Select & index a vault to see chunking status.")
                    .font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.outline)
            } else {
                ForEach(files.prefix(50)) { f in
                    HStack(spacing: 8) {
                        StatusDot(color: f.status == .synced ? Theme.Palette.success
                                  : f.status == .error ? Theme.Palette.error : Theme.Palette.primary,
                                  pulse: f.status == .indexing)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(f.fileName).font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
                                .lineLimit(1)
                            if !f.tags.isEmpty {
                                Text(f.tags.prefix(3).map { "#\($0)" }.joined(separator: " "))
                                    .font(Theme.Font.micro()).foregroundStyle(Theme.Palette.outline).lineLimit(1)
                            }
                        }
                        Spacer()
                        Text("\(f.chunkCount) ch").font(Theme.Font.bodySm().monospacedDigit())
                            .foregroundStyle(Theme.Palette.outline)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    // MARK: Vector DB stats

    private var vectorStats: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                MicroLabel(text: "Vector DB", color: Theme.Palette.success)
                Text("\(indexing.totalChunks()) vectors")
                    .font(Theme.Font.body().weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.Palette.onSurface)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("SQLite · cosine").font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.outline)
                Text(indexing.isIndexing ? "indexing…" : "ready")
                    .font(Theme.Font.bodySm())
                    .foregroundStyle(indexing.isIndexing ? Theme.Palette.primary : Theme.Palette.success)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}

/// A clickable source row (Inspector "Sources in this chat"): opens the exact file
/// on click, reveals in Finder from the context menu.
struct SourceRow: View {
    let citation: Citation
    @EnvironmentObject var projects: ProjectStore
    @State private var hover = false

    private var project: Project? { projects.project(id: citation.projectID) }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: SourceIcon.symbol(for: citation.fileName))
                .font(.system(size: 11)).foregroundStyle(Theme.Palette.primary)
            VStack(alignment: .leading, spacing: 1) {
                Text(citation.fileName).font(Theme.Font.bodySm().weight(.medium))
                    .foregroundStyle(Theme.Palette.onSurface).lineLimit(1)
                if let h = citation.heading, !h.isEmpty {
                    Text(h).font(Theme.Font.micro()).foregroundStyle(Theme.Palette.outline).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "arrow.up.forward.app").font(.system(size: 10))
                .foregroundStyle(hover ? Theme.Palette.primary : Theme.Palette.outline)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .glassCard(radius: Theme.Radius.sm, selected: hover)
        .contentShape(Rectangle())
        .onTapGesture {
            SourceOpener.open(project: project, relativePath: citation.filePath, fileName: citation.fileName)
        }
        .onHover { hover = $0 }
        .help("Open \(citation.fileName)")
        .contextMenu {
            Button("Open") {
                SourceOpener.open(project: project, relativePath: citation.filePath, fileName: citation.fileName)
            }
            Button("Reveal in Finder") {
                SourceOpener.reveal(project: project, relativePath: citation.filePath, fileName: citation.fileName)
            }
        }
    }
}
