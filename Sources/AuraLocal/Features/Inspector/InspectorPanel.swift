import SwiftUI

/// Right-side collapsible panel. Shows live retrieval context, indexed files in
/// the active vault with chunking status, and vector-DB statistics.
struct InspectorPanel: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var chat: ChatViewModel
    @EnvironmentObject var projects: ProjectStore
    @EnvironmentObject var indexing: IndexingService
    @EnvironmentObject var settingsStore: SettingsStore

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
            sliderRow(title: "Retrieval Count",
                      value: Binding(get: { Double(settingsStore.settings.retrievalTopK) },
                                     set: { settingsStore.settings.retrievalTopK = Int($0) }),
                      range: 1...50, step: 1,
                      label: "\(settingsStore.settings.retrievalTopK)")
            sliderRow(title: "Smart Scan Window",
                      value: Binding(get: { Double(settingsStore.settings.candidateFileWindow) },
                                     set: { settingsStore.settings.candidateFileWindow = Int($0) }),
                      range: 5...200, step: 5,
                      label: "\(settingsStore.settings.candidateFileWindow)")
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
        }
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>,
                           step: Double, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
                Spacer()
                Text(label).font(Theme.Font.bodySm().monospacedDigit()).foregroundStyle(Theme.Palette.primary)
            }
            Slider(value: value, in: range, step: step).controlSize(.mini).tint(Theme.Palette.primaryVivid)
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
