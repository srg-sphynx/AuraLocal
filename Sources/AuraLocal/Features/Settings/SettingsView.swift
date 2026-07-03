import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var inference: InferenceManager
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var indexing: IndexingService
    @EnvironmentObject var updater: UpdaterService
    @EnvironmentObject var theme: ThemeManager   // re-render in place on theme change

    @State private var showClearConfirm = false
    @State private var showResetConfirm = false
    @State private var autoUpdate = true
    @State private var showWhatsNew = false
    @State private var storage: StorageInfo.Report?
    @State private var reclaiming = false
    @State private var reclaimNote: String?

    private var s: Binding<AppSettings> { $settingsStore.settings }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(title: "Settings",
                              subtitle: "Configure local endpoints, model defaults, retrieval behavior and storage rules. Everything stays on-device.")
                EmbeddingStatusBanner()
                connections
                AutoConfigureCard()
                modelsAndGeneration
                ragSection
                AppearanceSettingsView()
                storageSection
                storageFootprintSection
                onboardingSection
                updatesSection
                dangerZone
                aboutSection
            }
            .padding(26)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .glassPane()
        .sheet(isPresented: $showWhatsNew) { WhatsNewView() }
        .task { await refreshStorage() }
    }

    // MARK: Connections

    private var connections: some View {
        SettingsCard(title: "Connections", symbol: "network") {
            connectionRow(name: "Ollama", online: inference.ollamaOnline,
                          url: s.ollamaBaseURL, key: s.ollamaAPIKey, placeholder: ProviderKind.ollama.defaultBaseURL)
            Divider().overlay(Theme.glassBorderSoft)
            connectionRow(name: "LM Studio", online: inference.lmStudioOnline,
                          url: s.lmStudioBaseURL, key: s.lmStudioAPIKey, placeholder: ProviderKind.lmstudio.defaultBaseURL)
            HStack {
                Spacer()
                Button { Task { await inference.refresh() } } label: {
                    Label("Test Connections", systemImage: "antenna.radiowaves.left.and.right").font(Theme.Font.bodySm())
                }.buttonStyle(GhostGlassButtonStyle())
            }
        }
    }

    private func connectionRow(name: String, online: Bool, url: Binding<String>, key: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatusDot(color: online ? Theme.Palette.success : Theme.Palette.error, pulse: online)
                Text(name).font(Theme.Font.body().weight(.semibold)).foregroundStyle(Theme.Palette.onSurface)
                Spacer()
                Text(online ? "Connected" : "Offline").font(Theme.Font.bodySm())
                    .foregroundStyle(online ? Theme.Palette.success : Theme.Palette.outline)
            }
            LabeledField(label: "Base URL") { GlassTextField(text: url, placeholder: placeholder) }
            LabeledField(label: "API Key (optional)") { GlassTextField(text: key, placeholder: "—", secure: true) }
        }
    }

    // MARK: Models & generation

    private var modelsAndGeneration: some View {
        SettingsCard(title: "Models & Generation", symbol: "cpu") {
            LabeledField(label: "Default Chat Model") {
                ModelMenu(selection: s.activeChatModel, provider: s.activeProvider,
                          models: inference.chatModels, fallback: "llama3")
            }
            LabeledField(label: "Default Embedding Model") {
                ModelMenu(selection: s.embeddingModel, provider: s.embeddingProvider,
                          models: inference.embeddingModels, fallback: "nomic-embed-text")
            }
            LabeledField(label: "System Prompt") {
                GlassTextEditor(text: s.systemPrompt, minHeight: 80)
            }
            sliderField("Temperature", value: s.temperature, range: 0...2, step: 0.05, fmt: "%.2f")
            sliderField("Top P", value: s.topP, range: 0...1, step: 0.05, fmt: "%.2f")
            intField("Context Length", value: s.contextLength, range: 512...131072, step: 512)
            intField("Max Output Tokens", value: s.maxTokens, range: 128...8192, step: 128)
        }
    }

    // MARK: RAG

    private var ragSection: some View {
        SettingsCard(title: "Retrieval & Chunking", symbol: "doc.text.magnifyingglass") {
            Toggle("Enable RAG by default", isOn: s.ragEnabledByDefault)
                .toggleStyle(.switch).tint(Theme.Palette.primaryVivid).font(Theme.Font.body())
            Toggle("Auto re-index on file save (live vault watching)", isOn: s.autoRefreshOnSave)
                .toggleStyle(.switch).tint(Theme.Palette.primaryVivid).font(Theme.Font.body())

            LabeledField(label: "Re-ranking") {
                Picker("", selection: s.rerankMode) {
                    ForEach(RerankMode.allCases) { Text($0.displayName).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
            }
            Text(settingsStore.settings.rerankMode.blurb)
                .font(Theme.Font.micro()).foregroundStyle(Theme.Palette.onSurfaceVariant)

            LabeledField(label: "Query expansion") {
                Picker("", selection: s.queryExpansion) {
                    ForEach(QueryExpansion.allCases) { Text($0.displayName).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
            }
            Text(settingsStore.settings.queryExpansion.blurb)
                .font(Theme.Font.micro()).foregroundStyle(Theme.Palette.onSurfaceVariant)

            Toggle("Fast ANN index (approximate search on large vaults)", isOn: s.annEnabled)
                .toggleStyle(.switch).tint(Theme.Palette.primaryVivid).font(Theme.Font.body())
            Toggle("Parent-document expansion (include neighboring chunks)", isOn: s.parentExpansion)
                .toggleStyle(.switch).tint(Theme.Palette.primaryVivid).font(Theme.Font.body())
            Toggle("Adaptive source cache (fast follow-ups within a chat's sources)", isOn: s.adaptiveSourceCache)
                .toggleStyle(.switch).tint(Theme.Palette.primaryVivid).font(Theme.Font.body())
            if settingsStore.settings.adaptiveSourceCache {
                sliderField("Cache reuse threshold", value: s.adaptiveReuseThreshold, range: 0.4...0.9, step: 0.01, fmt: "%.2f")
            }

            intField("Max sources per answer (Top-K)", value: s.retrievalTopK, range: 1...100, step: 1)
            intField("Smart Scan window (keyword candidate files)", value: s.candidateFileWindow, range: 5...200, step: 5)
            intField("Semantic candidates / query", value: s.semanticCandidateCount, range: 20...1000, step: 20)
            intField("History turns folded into retrieval", value: s.historyTurnsForRetrieval, range: 0...6, step: 1)
            sliderField("Minimum Similarity", value: s.minSimilarity, range: 0...1, step: 0.01, fmt: "%.2f")
            intField("Chunk Size (tokens)", value: s.chunkMaxTokens, range: 128...2048, step: 64)
            intField("Chunk Overlap (tokens)", value: s.chunkOverlap, range: 0...256, step: 16)
            Text("Every note is embedded up-front, so queries only embed the query. Retrieval fuses keyword (BM25) + semantic (cosine) candidates with RRF and folds recent turns in so follow-ups keep their context. The ANN index keeps semantic search fast as the vault grows; it falls back to an exact scan automatically. The adaptive source cache maps the sources each chat has pulled so in-topic follow-ups answer without a full re-scan — a question about new material always searches the whole vault again.")
                .font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
        }
    }

    // MARK: Onboarding & help

    private var onboardingSection: some View {
        SettingsCard(title: "Getting Started", symbol: "graduationcap") {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Setup walkthrough").font(Theme.Font.body().weight(.semibold)).foregroundStyle(Theme.Palette.onSurface)
                    Text("Replay the guided tour: connect a model, add a vault, and ask your first question.")
                        .font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button {
                    settingsStore.settings.hasCompletedOnboarding = false
                } label: { Label("Replay", systemImage: "play.circle").font(Theme.Font.bodySm()) }
                    .buttonStyle(GhostGlassButtonStyle())
            }
        }
    }

    // MARK: Storage

    private var storageSection: some View {
        SettingsCard(title: "Storage & Indexing Rules", symbol: "externaldrive") {
            LabeledField(label: "Vector Store Path") {
                HStack {
                    GlassTextField(text: s.vectorStorePath, placeholder: AppPaths.defaultDatabaseFile.path)
                    Button { revealDB() } label: { Image(systemName: "folder") }.buttonStyle(GhostGlassButtonStyle())
                }
            }
            LabeledField(label: "Included Extensions") {
                GlassTextField(text: Binding(
                    get: { settingsStore.settings.includedExtensions.joined(separator: ", ") },
                    set: { settingsStore.settings.includedExtensions = parseList($0) }), placeholder: "md, txt, pdf")
            }
            LabeledField(label: "Excluded Patterns (.obsidian auto-excluded)") {
                GlassTextEditor(text: Binding(
                    get: { settingsStore.settings.excludedPatterns.joined(separator: ", ") },
                    set: { settingsStore.settings.excludedPatterns = parseList($0) }), minHeight: 60)
            }
            intField("Max file size (MB) — larger files are skipped", value: s.maxFileSizeMB, range: 1...512, step: 1)
            Toggle("OCR scanned PDF pages (slower)", isOn: s.pdfOCRFallback)
                .toggleStyle(.switch).tint(Theme.Palette.primaryVivid).font(Theme.Font.body())
            Text("Supported: Markdown, PDF, Word (.docx), HTML, EPUB, RTF, CSV/TSV, wiki (MediaWiki), and plain text. Code files are supported but off by default — add their extensions above to include them. Hidden config folders and media assets are always skipped.")
                .font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
        }
    }

    // MARK: On-disk footprint & maintenance

    private var storageFootprintSection: some View {
        SettingsCard(title: "On-Disk Footprint", symbol: "internaldrive") {
            if let r = storage {
                storageRow("Vector index", r.index, "Embeddings + keyword index for your vaults.")
                storageRow("Fast-search cache", r.fastCache, "Approximate-index sidecars. Regenerated automatically when needed.")
                storageRow("Chats", r.chats, "Your saved conversations.")
                storageRow("Settings & vaults", r.meta, "Preferences and vault registrations.")
                if r.other > 0 { storageRow("Other", r.other, "Anything else under Aura's data folder.") }
                Divider().overlay(Theme.glassBorderSoft)
                HStack {
                    Text("Total on disk").font(Theme.Font.body().weight(.semibold))
                        .foregroundStyle(Theme.Palette.onSurface)
                    Spacer()
                    Text(StorageInfo.humanized(r.total)).font(Theme.Font.body().weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.Palette.onSurface)
                }
            } else {
                Text("Measuring…").font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.outline)
            }
            Text("Everything Aura stores lives in one folder — nothing is scattered elsewhere. Removing a vault erases its vectors automatically; deleting a chat frees its cached sources. Use Reclaim to compact free space left by deletions.")
                .font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
            HStack(spacing: 10) {
                Button { Task { await reclaim() } } label: {
                    Label(reclaiming ? "Reclaiming…" : "Reclaim disk space", systemImage: "arrow.down.circle")
                        .font(Theme.Font.bodySm())
                }.buttonStyle(GhostGlassButtonStyle()).disabled(reclaiming)
                Button { revealDB() } label: {
                    Label("Show data folder", systemImage: "folder").font(Theme.Font.bodySm())
                }.buttonStyle(GhostGlassButtonStyle())
                if let note = reclaimNote {
                    Text(note).font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.success)
                }
                Spacer()
            }
        }
    }

    private func storageRow(_ title: String, _ bytes: Int64, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.Font.bodySm().weight(.medium)).foregroundStyle(Theme.Palette.onSurfaceVariant)
                Text(detail).font(Theme.Font.micro()).foregroundStyle(Theme.Palette.outline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(StorageInfo.humanized(bytes)).font(Theme.Font.bodySm().monospacedDigit())
                .foregroundStyle(Theme.Palette.onSurface)
        }
    }

    @MainActor private func refreshStorage() async {
        let url = settingsStore.databaseURL
        let report = await Task.detached(priority: .utility) { StorageInfo.snapshot(databaseURL: url) }.value
        storage = report
    }

    @MainActor private func reclaim() async {
        guard !reclaiming else { return }
        reclaiming = true; reclaimNote = nil
        let freed: Int64 = await withCheckedContinuation { cont in
            indexing.reclaimDiskSpace { bytes in cont.resume(returning: bytes) }
        }
        await refreshStorage()
        reclaiming = false
        reclaimNote = freed > 0 ? "Freed \(StorageInfo.humanized(freed))" : "Already compact"
    }

    // MARK: Software updates

    private var updatesSection: some View {
        SettingsCard(title: "Software Updates", symbol: "arrow.down.circle") {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current version").font(Theme.Font.body().weight(.semibold)).foregroundStyle(Theme.Palette.onSurface)
                    Text("You're on Aura Local \(AppInfo.versionDisplay) (build \(AppInfo.build)).")
                        .font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
                }
                Spacer(minLength: 8)
                Button { showWhatsNew = true } label: {
                    Label("What's New", systemImage: "sparkles").font(Theme.Font.bodySm())
                }.buttonStyle(GhostGlassButtonStyle())
            }
            Divider().overlay(Theme.glassBorderSoft)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatic updates").font(Theme.Font.body().weight(.semibold)).foregroundStyle(Theme.Palette.onSurface)
                    Text("Check for new versions in the background and notify you when one is ready to install.")
                        .font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: $autoUpdate)
                    .labelsHidden().toggleStyle(.switch).tint(Theme.Palette.primaryVivid)
                    .onChange(of: autoUpdate) { _, on in updater.automaticallyChecksForUpdates = on }
            }
            Divider().overlay(Theme.glassBorderSoft)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Check now").font(Theme.Font.body().weight(.semibold)).foregroundStyle(Theme.Palette.onSurface)
                    Text("Update feed: \(updater.feedURLString)")
                        .font(Theme.Font.micro()).foregroundStyle(Theme.Palette.outline)
                        .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Button { updater.checkForUpdates() } label: {
                    Label("Check for Updates", systemImage: "arrow.down.circle").font(Theme.Font.bodySm())
                }
                .buttonStyle(GhostGlassButtonStyle())
                .disabled(!updater.canCheckForUpdates)
            }
        }
        .onAppear { autoUpdate = updater.automaticallyChecksForUpdates }
    }

    // MARK: Danger zone

    private var dangerZone: some View {
        SettingsCard(title: "Danger Zone", symbol: "exclamationmark.triangle") {
            dangerRow(title: "Clear index & chats",
                      detail: "Removes all vectors, indexed files, vaults, and chat history. Keeps your settings and theme.",
                      button: "Clear", destructiveTitle: false) { showClearConfirm = true }
            Divider().overlay(Theme.glassBorderSoft)
            dangerRow(title: "Delete all data (factory reset)",
                      detail: "Erases everything above plus all settings, endpoints, and themes — the app returns to first-launch state.",
                      button: "Delete All", destructiveTitle: true) { showResetConfirm = true }
        }
        .confirmationDialog("Clear the index and all chats?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear index & chats", role: .destructive) { env.clearIndexAndChats(); Task { await refreshStorage() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes all vectors, indexed files, vaults, and chat history. Your settings are kept. This can't be undone.")
        }
        .confirmationDialog("Delete ALL Aura data?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { env.factoryReset(); Task { await refreshStorage() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Erases the index, chats, vaults, and all settings/themes. The app returns to first-launch state. This can't be undone.")
        }
    }

    private func dangerRow(title: String, detail: String, button: String,
                           destructiveTitle: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Font.body().weight(.semibold))
                    .foregroundStyle(destructiveTitle ? Theme.Palette.error : Theme.Palette.onSurface)
                Text(detail).font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.outline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(role: .destructive, action: action) {
                Label(button, systemImage: "trash").font(Theme.Font.bodySm())
            }.buttonStyle(GhostGlassButtonStyle())
        }
    }

    private var aboutSection: some View {
        SettingsCard(title: "About", symbol: "info.circle") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aura Local").font(Theme.Font.body().weight(.semibold)).foregroundStyle(Theme.Palette.onSurface)
                    Text("Local RAG chat for Ollama & LM Studio · \(AppInfo.versionDisplay)")
                        .font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.outline)
                }
                Spacer()
                Button { showWhatsNew = true } label: {
                    Label("What's New", systemImage: "sparkles").font(Theme.Font.bodySm())
                }.buttonStyle(GhostGlassButtonStyle())
                Text("100% on-device").font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.success)
            }
        }
    }

    // MARK: helpers

    private func sliderField(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, fmt: String) -> some View {
        LabeledField(label: title) {
            HStack(spacing: 12) {
                Slider(value: value, in: range, step: step).tint(Theme.Palette.primaryVivid)
                Text(String(format: fmt, value.wrappedValue)).font(Theme.Font.body().monospacedDigit())
                    .foregroundStyle(Theme.Palette.primary).frame(width: 56, alignment: .trailing)
            }
        }
    }
    private func intField(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int) -> some View {
        LabeledField(label: title) {
            HStack(spacing: 12) {
                Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) }),
                       in: Double(range.lowerBound)...Double(range.upperBound), step: Double(step))
                    .tint(Theme.Palette.primaryVivid)
                Text("\(value.wrappedValue)").font(Theme.Font.body().monospacedDigit())
                    .foregroundStyle(Theme.Palette.primary).frame(width: 64, alignment: .trailing)
            }
        }
    }
    private func parseList(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == "," || $0 == "\n" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    private func revealDB() {
        NSWorkspace.shared.activateFileViewerSelecting([settingsStore.databaseURL])
    }
}

// MARK: - Settings building blocks

struct SettingsCard<Content: View>: View {
    let title: String; let symbol: String; @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Theme.Palette.primary)
                Text(title).font(Theme.Font.titleSm()).foregroundStyle(Theme.Palette.onSurface)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: Theme.Radius.lg)
    }
}

struct LabeledField<Content: View>: View {
    let label: String; @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
            content
        }
    }
}

struct GlassTextField: View {
    @Binding var text: String
    var placeholder: String = ""
    var secure: Bool = false
    var body: some View {
        Group {
            if secure { SecureField(placeholder, text: $text) }
            else { TextField(placeholder, text: $text) }
        }
        .textFieldStyle(.plain)
        .font(Theme.Font.body())
        .foregroundStyle(Theme.Palette.onSurface)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Palette.fieldFill))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).strokeBorder(Theme.glassBorderSoft, lineWidth: 0.5))
    }
}

struct GlassTextEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = 60
    var body: some View {
        TextEditor(text: $text)
            .font(Theme.Font.body())
            .foregroundStyle(Theme.Palette.onSurface)
            .scrollContentBackground(.hidden)
            .frame(minHeight: minHeight)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Palette.fieldFill))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).strokeBorder(Theme.glassBorderSoft, lineWidth: 0.5))
    }
}

struct ModelMenu: View {
    @Binding var selection: String
    @Binding var provider: ProviderKind
    let models: [ModelInfo]
    let fallback: String
    var body: some View {
        Menu {
            if models.isEmpty { Text("No models discovered") }
            ForEach(models) { m in
                Button("\(m.name)  ·  \(m.provider.displayName)") { selection = m.name; provider = m.provider }
            }
            Divider()
            Button("Use “\(fallback)”") { selection = fallback }
        } label: {
            HStack {
                Text(selection.isEmpty ? fallback : selection).font(Theme.Font.body()).foregroundStyle(Theme.Palette.onSurface)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(Theme.Palette.outline)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Palette.fieldFill))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).strokeBorder(Theme.glassBorderSoft, lineWidth: 0.5))
        }.menuStyle(.borderlessButton)
    }
}
