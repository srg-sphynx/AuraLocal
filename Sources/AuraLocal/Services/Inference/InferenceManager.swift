import Foundation
import Combine

/// Coordinates connectors, tracks reachability + per-model load state, and exposes
/// discovered models plus a live readiness signal for the embedding model.
@MainActor
final class InferenceManager: ObservableObject {
    @Published var ollamaOnline = false
    @Published var lmStudioOnline = false
    @Published var models: [ModelInfo] = []
    @Published var isRefreshing = false
    @Published var lastError: String?

    /// Live readiness of the configured embedding model (drives the UI banner).
    @Published var embeddingStatus: EmbeddingStatus = .notConfigured
    /// Verified embedding dimensionality from the last successful probe.
    @Published var embeddingDim: Int?

    /// Fallback discovery source while the Ollama server is offline (wired to
    /// `OllamaControlService.installedCatalog` — reads `ollama list` via the CLI).
    /// Keeps Auto-Configure / Model Zoo truthful about what's actually installed.
    var offlineCatalog: (() async -> [ModelInfo])?

    private unowned let settingsStore: SettingsStore
    private var pollTask: Task<Void, Never>?
    private var probeInFlight = false
    private var probedKey: String?        // "provider/model" that probed OK

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    private var settings: AppSettings { settingsStore.settings }

    func provider(_ kind: ProviderKind) -> InferenceProvider {
        ProviderFactory.make(kind, settings: settings)
    }

    var activeProvider: InferenceProvider { provider(settings.activeProvider) }

    var isActiveOnline: Bool {
        settings.activeProvider == .ollama ? ollamaOnline : lmStudioOnline
    }

    var embeddingReady: Bool { embeddingStatus.isReady }

    func isOnline(_ kind: ProviderKind) -> Bool {
        kind == .ollama ? ollamaOnline : lmStudioOnline
    }

    /// Lightweight reachability + model list refresh, then re-assess embedding state.
    /// `quiet` (used by the background poll) skips the `isRefreshing` spinner so a
    /// routine poll doesn't publish twice to every observing view.
    func refresh(quiet: Bool = false) async {
        if !quiet { isRefreshing = true }
        defer { if !quiet { isRefreshing = false } }

        let ollama = ProviderFactory.make(.ollama, settings: settings)
        let lmstudio = ProviderFactory.make(.lmstudio, settings: settings)

        async let oOnline = ollama.ping()
        async let lOnline = lmstudio.ping()
        let o = await oOnline
        let l = await lOnline
        // Publish only actual changes — @Published fires on every assignment, and
        // this runs on a timer.
        if ollamaOnline != o { ollamaOnline = o }
        if lmStudioOnline != l { lmStudioOnline = l }

        var discovered: [ModelInfo] = []
        if o {
            discovered += (try? await ollama.listModels()) ?? []
        } else if let fallback = offlineCatalog {
            // Server down ≠ nothing installed: surface the on-disk catalog.
            discovered += await fallback()
        }
        if l { discovered += (try? await lmstudio.listModels()) ?? [] }
        if models != discovered { models = discovered }

        // Auto-pick a sensible default chat model if none is set (prefer LM Studio,
        // the intended chat runtime; fall back to any discovered chat model).
        if settingsStore.settings.activeChatModel.isEmpty,
           let first = discovered.first(where: { $0.provider == .lmstudio && !$0.isEmbedding })
                       ?? discovered.first(where: { !$0.isEmbedding }) {
            settingsStore.settings.activeProvider = first.provider
            settingsStore.settings.activeChatModel = first.name
        }

        // Auto-pick an embedding model only if none is configured (prefer Ollama).
        if settingsStore.settings.embeddingModel.isEmpty,
           let emb = discovered.first(where: { $0.provider == .ollama && $0.isEmbedding })
                     ?? discovered.first(where: { $0.isEmbedding }) {
            settingsStore.settings.embeddingProvider = emb.provider
            settingsStore.settings.embeddingModel = emb.name
        }

        reassessEmbedding()
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(quiet: true)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    func stopPolling() { pollTask?.cancel() }

    var chatModels: [ModelInfo] { models.filter { !$0.isEmbedding } }
    var embeddingModels: [ModelInfo] { models.filter { $0.isEmbedding } }

    /// One-shot, non-streamed completion (accumulates the stream). Best-effort:
    /// returns nil on any failure or when no chat model is configured. Used by the
    /// optional retrieval enhancers (query expansion / LLM re-rank).
    func complete(prompt: String, system: String = "You are a helpful assistant.",
                  maxTokens: Int = 256, temperature: Double = 0.0) async -> String? {
        let s = settings
        guard !s.activeChatModel.isEmpty else { return nil }
        let config = GenerationConfig(model: s.activeChatModel, systemPrompt: system,
                                      temperature: temperature, topP: s.topP,
                                      contextLength: s.contextLength, maxTokens: maxTokens)
        let messages = [ChatMessage(role: .user, text: prompt)]
        var out = ""
        do {
            for try await token in activeProvider.streamChat(messages: messages, config: config) {
                out += token.text
                if token.done { break }
            }
        } catch { return nil }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Active chat node state

    /// Live state of the configured chat model — drives the "Current Active Node"
    /// card and anywhere else that must reflect reality, not just the setting.
    enum ActiveNodeState: Equatable {
        case none          // no chat model selected
        case offline       // provider server unreachable
        case missing       // provider online but model not in its catalog
        case ready         // installed; loads on first use
        case loaded        // resident in memory now
    }

    /// The discovered record matching the configured chat model, tolerating
    /// Ollama's implicit `:latest` tag (same matching rules as embeddings).
    func matchedChatModel() -> ModelInfo? {
        let name = settings.activeChatModel
        guard !name.isEmpty else { return nil }
        let pool = models.filter { $0.provider == settings.activeProvider }
        if let m = pool.first(where: { $0.name == name }) { return m }
        if let m = pool.first(where: { $0.name == name + ":latest" || $0.name + ":latest" == name }) { return m }
        return pool.first { $0.name.hasPrefix(name + ":") }
    }

    var activeNodeState: ActiveNodeState {
        guard !settings.activeChatModel.isEmpty else { return .none }
        guard isActiveOnline else { return .offline }
        guard let m = matchedChatModel() else { return .missing }
        return m.loaded ? .loaded : .ready
    }

    // MARK: - Embedding readiness

    /// The discovered model record that matches the configured embedding model,
    /// tolerating Ollama's implicit `:latest` tag.
    func matchedEmbeddingModel() -> ModelInfo? {
        let name = settings.embeddingModel
        guard !name.isEmpty else { return nil }
        let pool = models.filter { $0.provider == settings.embeddingProvider }
        if let m = pool.first(where: { $0.name == name }) { return m }
        if let m = pool.first(where: { $0.name == name + ":latest" || $0.name + ":latest" == name }) { return m }
        if let m = pool.first(where: { $0.name.hasPrefix(name + ":") }) { return m }
        return nil
    }

    /// Re-derive `embeddingStatus` from current online flags + model catalog, and
    /// kick a one-shot readiness probe when warranted. Call after changing the
    /// embedding model/provider in the UI, or it runs on each poll.
    func reassessEmbedding() {
        let prov = settings.embeddingProvider
        let model = settings.embeddingModel
        guard !model.isEmpty else { setStatus(.notConfigured); return }
        guard isOnline(prov) else { setStatus(.providerOffline); return }
        guard let matched = matchedEmbeddingModel() else { setStatus(.modelNotFound); return }

        let key = "\(prov.rawValue)/\(matched.name)"
        // LM Studio: don't auto-load — require the user to have it resident.
        // Ollama: auto-loads reliably on first call, so catalog presence is enough.
        if prov == .lmstudio && !matched.loaded { setStatus(.notLoaded); return }

        if probedKey == key, let dim = embeddingDim { setStatus(.ready(dim: dim)); return }
        guard !probeInFlight else { return }
        probeInFlight = true
        if !embeddingStatus.isReady { embeddingStatus = .loading }
        Task { await probeEmbedding(provider: prov, model: matched.name, key: key) }
    }

    private func setStatus(_ s: EmbeddingStatus) {
        if embeddingStatus != s { embeddingStatus = s }   // runs on every poll — publish diffs only
        if !s.isReady { probedKey = nil }
    }

    private func probeEmbedding(provider: ProviderKind, model: String, key: String) async {
        defer { probeInFlight = false }
        let p = ProviderFactory.make(provider, settings: settings)
        do {
            let vecs = try await p.embed(texts: ["aura embedding readiness probe"], model: model)
            if let v = vecs.first, !v.isEmpty {
                embeddingDim = v.count
                probedKey = key
                embeddingStatus = .ready(dim: v.count)
            } else {
                embeddingStatus = .error("empty embedding")
            }
        } catch {
            embeddingStatus = .error(Self.shortError(error))
        }
    }

    static func shortError(_ error: Error) -> String {
        let d = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return String(d.prefix(120))
    }
}
