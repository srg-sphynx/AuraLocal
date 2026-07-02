import SwiftUI

struct KnowledgeBaseView: View {
    @EnvironmentObject var projects: ProjectStore
    @EnvironmentObject var indexing: IndexingService
    @EnvironmentObject var inference: InferenceManager
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header
                EmbeddingStatusBanner()
                statRow
                sourcesSection
                indexingEngine
            }
            .padding(26)
        }
        .glassPane()
    }

    private var header: some View {
        HStack(alignment: .top) {
            SectionHeader(title: "Knowledge Base",
                          subtitle: "Manage the local sources for Retrieval-Augmented Generation. Vaults are parsed, chunked and vectorized for private, on-device interactions.")
            Spacer()
            HStack(spacing: 10) {
                Button { projects.addVault() } label: { Label("Add Vault", systemImage: "plus") }
                    .buttonStyle(GhostGlassButtonStyle())
                Button {
                    if let p = projects.selectedProject { projects.reindex(p) }
                } label: { Label("Scan Now", systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(PrimaryGlassButtonStyle())
                    .disabled(projects.selectedProject == nil)
            }
        }
    }

    private var statRow: some View {
        HStack(spacing: 14) {
            StatCard(label: "Total Vectors", value: "\(indexing.totalChunks())", tint: Theme.Palette.primary, symbol: "cube.transparent")
            StatCard(label: "Indexed Sources", value: "\(totalFiles)", tint: Theme.Palette.secondary, symbol: "doc.on.doc")
            StatCard(label: "Vaults", value: "\(projects.projects.count)", tint: Theme.Palette.primary, symbol: "circle.hexagongrid")
            StatCard(label: "System Status",
                     value: indexing.isIndexing ? "Indexing" : "Synced",
                     tint: indexing.isIndexing ? Theme.Palette.warning : Theme.Palette.success,
                     symbol: indexing.isIndexing ? "bolt.fill" : "checkmark.seal.fill")
        }
    }

    private var totalFiles: Int {
        projects.projects.reduce(0) { $0 + (indexing.indexedFiles[$1.id]?.count ?? 0) }
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MicroLabel(text: "Active Vaults & Sources")
            if projects.projects.isEmpty {
                AddSourceCard().frame(maxWidth: 320)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                    ForEach(projects.projects) { p in
                        VaultSourceCard(project: p, fileCount: indexing.indexedFiles[p.id]?.count ?? 0,
                                        chunkCount: indexing.chunkCount(for: p.id))
                    }
                    AddSourceCard()
                }
            }
        }
    }

    private var indexingEngine: some View {
        VStack(alignment: .leading, spacing: 14) {
            MicroLabel(text: "Global Indexing Engine")
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Embedding Model").font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
                    Menu {
                        ForEach(inference.embeddingModels) { m in
                            Button("\(m.name)\(m.loaded ? "  ●" : "")") {
                                settingsStore.settings.embeddingProvider = m.provider
                                settingsStore.settings.embeddingModel = m.name
                                inference.reassessEmbedding()
                            }
                        }
                        Divider()
                        Button("bge-m3") { settingsStore.settings.embeddingProvider = .ollama; settingsStore.settings.embeddingModel = "bge-m3"; inference.reassessEmbedding() }
                        Button("qwen3-embedding:0.6b") { settingsStore.settings.embeddingProvider = .ollama; settingsStore.settings.embeddingModel = "qwen3-embedding:0.6b"; inference.reassessEmbedding() }
                    } label: {
                        HStack {
                            Text(settingsStore.settings.embeddingModel.isEmpty ? "bge-m3" : settingsStore.settings.embeddingModel)
                                .font(Theme.Font.body())
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
                        }
                        .foregroundStyle(Theme.Palette.onSurface)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Palette.fieldFill))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).strokeBorder(Theme.glassBorderSoft, lineWidth: 0.5))
                    }.menuStyle(.borderlessButton).frame(width: 230)
                    Text("Embeddings run on Ollama. Changing the model re-embeds the vault on the next index; text stays keyword-searchable throughout.")
                        .font(Theme.Font.micro()).foregroundStyle(Theme.Palette.outline).fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Chunk Size (tokens)").font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
                        Spacer()
                        Text("\(settingsStore.settings.chunkMaxTokens)").font(Theme.Font.bodySm().monospacedDigit())
                            .foregroundStyle(Theme.Palette.primary)
                    }
                    Slider(value: Binding(get: { Double(settingsStore.settings.chunkMaxTokens) },
                                          set: { settingsStore.settings.chunkMaxTokens = Int($0) }),
                           in: 128...2048, step: 64).tint(Theme.Palette.primaryVivid)
                    Text("Header-aware semantic splitting; controls the soft per-chunk budget.")
                        .font(Theme.Font.micro()).foregroundStyle(Theme.Palette.outline)
                }
                .frame(width: 260)

                VStack(alignment: .leading, spacing: 8) {
                    Text("RAG Optimization").font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
                    Toggle("Hybrid re-ranking", isOn: Binding(
                        get: { settingsStore.settings.rerankMode != .off },
                        set: { settingsStore.settings.rerankMode = $0 ? .hybridRRF : .off }))
                        .toggleStyle(.switch).controlSize(.small).tint(Theme.Palette.primaryVivid)
                        .font(Theme.Font.bodySm())
                    Toggle("Auto-refresh on save", isOn: $settingsStore.settings.autoRefreshOnSave)
                        .toggleStyle(.switch).controlSize(.small).tint(Theme.Palette.primaryVivid)
                        .font(Theme.Font.bodySm())
                }
            }
            .padding(16)
            .glassCard(radius: Theme.Radius.lg)
        }
    }
}

struct StatCard: View {
    let label: String
    let value: String
    var tint: Color = Theme.Palette.primary
    var symbol: String = "circle"
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(tint)
                Spacer()
            }
            Text(value).font(Theme.Font.statLg()).foregroundStyle(Theme.Palette.onSurface)
            MicroLabel(text: label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(radius: Theme.Radius.lg)
    }
}

struct VaultSourceCard: View {
    let project: Project
    let fileCount: Int
    let chunkCount: Int
    @EnvironmentObject var projects: ProjectStore
    @EnvironmentObject var indexing: IndexingService

    private var isActive: Bool { indexing.isIndexing && indexing.activeProjectID == project.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: project.kind == .obsidian ? "circle.hexagongrid.fill" : "folder.fill")
                    .foregroundStyle(Theme.Palette.primary)
                Text(project.name).font(Theme.Font.titleSm()).foregroundStyle(Theme.Palette.onSurface).lineLimit(1)
                Spacer()
                StatusChip(text: statusText, color: statusColor)
            }
            Text(project.path).font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.outline).lineLimit(1)

            if isActive {
                VStack(alignment: .leading, spacing: 4) {
                    Text(indexing.statusMessage).font(Theme.Font.micro()).foregroundStyle(Theme.Palette.primary).lineLimit(1)
                    BarMeter(value: indexing.progress, tint: Theme.Palette.primary)
                }
            } else {
                HStack(spacing: 16) {
                    metric("\(fileCount)", "files")
                    metric("\(chunkCount)", "chunks")
                    metric("\(indexing.embeddedCount(for: project.id))", "vectors")
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "bolt.horizontal.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.Palette.primary)
                Text("Full Embed — vectorized up-front for instant, consistent retrieval")
                    .font(Theme.Font.micro()).foregroundStyle(Theme.Palette.outline).lineLimit(2)
            }

            HStack(spacing: 8) {
                Button { projects.reindex(project) } label: {
                    Label("Re-index", systemImage: "arrow.triangle.2.circlepath").font(Theme.Font.bodySm())
                }.buttonStyle(GhostGlassButtonStyle())
                Button {
                    if let url = try? BookmarkStore.resolve(project.bookmark).url {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } label: { Label("Files", systemImage: "folder").font(Theme.Font.bodySm()) }
                    .buttonStyle(GhostGlassButtonStyle())
                Spacer()
                Button { projects.removeProject(project) } label: {
                    Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(Theme.Palette.outline)
                }.buttonStyle(.plain)
            }
        }
        .padding(14)
        .glassCard(radius: Theme.Radius.lg)
    }

    private func metric(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(Theme.Font.body().weight(.semibold).monospacedDigit()).foregroundStyle(Theme.Palette.onSurface)
            Text(l).font(Theme.Font.micro()).foregroundStyle(Theme.Palette.outline)
        }
    }
    private var statusText: String {
        if isActive { return "Indexing" }
        switch project.status {
        case .synced: return "Synced"; case .error: return "Error"; default: return chunkCount > 0 ? "Synced" : "Pending"
        }
    }
    private var statusColor: Color {
        if isActive { return Theme.Palette.primary }
        switch project.status {
        case .error: return Theme.Palette.error
        default: return chunkCount > 0 ? Theme.Palette.success : Theme.Palette.outline
        }
    }
    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }
}

struct AddSourceCard: View {
    @EnvironmentObject var projects: ProjectStore
    var body: some View {
        Button { projects.addVault() } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus.circle").font(.system(size: 24)).foregroundStyle(Theme.Palette.primary)
                Text("Add Source").font(Theme.Font.body().weight(.semibold)).foregroundStyle(Theme.Palette.onSurface)
                Text("Local folder or vault").font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.outline)
            }
            .frame(maxWidth: .infinity, minHeight: 140)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.Palette.cardFill))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(Theme.glassBorder))
        }.buttonStyle(.plain)
    }
}
