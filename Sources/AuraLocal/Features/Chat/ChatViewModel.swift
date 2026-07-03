import Foundation
import Combine

/// Owns chat sessions and drives a single streamed completion, optionally
/// augmented with retrieved vault context (RAG). Tracks token-generation speed.
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var sessions: [ChatSession] = []
    @Published var currentSessionID: UUID?
    @Published var draft: String = ""
    @Published var ragEnabled: Bool
    @Published var isGenerating = false
    @Published var liveTokensPerSecond: Double = 0
    @Published var lastRetrieval: [RetrievedChunk] = []
    @Published var lastRetrievalQuery: String = ""

    private unowned let settingsStore: SettingsStore
    private unowned let inference: InferenceManager
    private unowned let indexing: IndexingService
    private unowned let projects: ProjectStore
    private var streamTask: Task<Void, Never>?

    init(settingsStore: SettingsStore, inference: InferenceManager,
         indexing: IndexingService, projects: ProjectStore) {
        self.settingsStore = settingsStore
        self.inference = inference
        self.indexing = indexing
        self.projects = projects
        self.ragEnabled = settingsStore.settings.ragEnabledByDefault
        load()
        if sessions.isEmpty { newSession() }
    }

    private var settings: AppSettings { settingsStore.settings }

    var currentSession: ChatSession? {
        sessions.first { $0.id == currentSessionID }
    }
    private var currentIndex: Int? {
        sessions.firstIndex { $0.id == currentSessionID }
    }

    // MARK: - Session management

    func newSession() {
        let s = ChatSession(title: "New Chat", projectID: projects.selectedProjectID)
        sessions.insert(s, at: 0)
        currentSessionID = s.id
        lastRetrieval = []
    }

    func selectSession(_ id: UUID) { currentSessionID = id }

    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if currentSessionID == id { currentSessionID = sessions.first?.id }
        if sessions.isEmpty { newSession() }
        save()
    }

    func stop() {
        streamTask?.cancel()
        isGenerating = false
        if let i = currentIndex, let last = sessions[i].messages.indices.last {
            sessions[i].messages[last].isStreaming = false
        }
    }

    // MARK: - Send

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating, let idx = currentIndex else { return }
        draft = ""

        sessions[idx].messages.append(ChatMessage(role: .user, text: text))
        if sessions[idx].title == "New Chat" {
            sessions[idx].title = String(text.prefix(40))
        }
        sessions[idx].updatedAt = Date()

        streamTask = Task { await runCompletion(userText: text) }
    }

    private func runCompletion(userText: String) async {
        guard let idx = currentIndex else { return }
        isGenerating = true
        liveTokensPerSecond = 0
        defer { isGenerating = false }

        // 1. Retrieval (RAG)
        var citations: [Citation] = []
        var contextBlock = ""
        if ragEnabled, let project = projects.selectedProject {
            lastRetrievalQuery = userText
            let retrievalQuery = Self.retrievalQuery(messages: sessions[idx].messages,
                                                     current: userText,
                                                     turns: settings.historyTurnsForRetrieval)
            let chunks = await retrieveWithExpansion(baseQuery: retrievalQuery, userText: userText, project: project)
            lastRetrieval = chunks
            if !chunks.isEmpty {
                contextBlock = Self.buildContext(chunks)
                citations = chunks.map {
                    Citation(fileName: $0.fileName, filePath: $0.filePath, projectID: project.id,
                             heading: $0.heading, snippet: String($0.text.prefix(220)), score: $0.score)
                }
            }
        } else {
            lastRetrieval = []
        }

        // 2. Compose message history (+ context preamble on the latest user turn)
        var history = sessions[idx].messages.filter { $0.role != .system }
        if !contextBlock.isEmpty, let lastUser = history.lastIndex(where: { $0.role == .user }) {
            history[lastUser].text = """
            Use the following context from my vault to answer. Cite note titles in brackets.

            <context>
            \(contextBlock)
            </context>

            Question: \(userText)
            """
        }

        // 3. Assistant placeholder
        let assistant = ChatMessage(role: .assistant, text: "", citations: citations,
                                    modelName: settings.activeChatModel, isStreaming: true)
        sessions[idx].messages.append(assistant)
        let assistantPos = sessions[idx].messages.count - 1

        // 4. Stream
        let provider = inference.activeProvider
        let config = GenerationConfig(model: settings.activeChatModel,
                                      systemPrompt: settings.systemPrompt,
                                      temperature: settings.temperature,
                                      topP: settings.topP,
                                      contextLength: settings.contextLength,
                                      maxTokens: settings.maxTokens)

        guard !settings.activeChatModel.isEmpty else {
            sessions[idx].messages[assistantPos].text = "⚠️ No model selected. Open **Model Zoo** or **Settings** to choose a local model."
            sessions[idx].messages[assistantPos].isStreaming = false
            save(); return
        }

        let start = Date()
        var charCount = 0
        var finalEvalCount: Int?
        var finalEvalNs: Int64?

        do {
            for try await token in provider.streamChat(messages: history, config: config) {
                if Task.isCancelled { break }
                if !token.text.isEmpty {
                    sessions[idx].messages[assistantPos].text += token.text
                    charCount += token.text.count
                    let elapsed = Date().timeIntervalSince(start)
                    if elapsed > 0.2 {
                        liveTokensPerSecond = (Double(charCount) / 4.0) / elapsed  // ~4 chars/token
                    }
                }
                if let ec = token.evalCount { finalEvalCount = ec }
                if let ed = token.evalDurationNs { finalEvalNs = ed }
                if token.done { break }
            }
        } catch {
            sessions[idx].messages[assistantPos].text += "\n\n⚠️ \(error.localizedDescription)"
        }

        // 5. Finalize stats
        let elapsed = max(0.001, Date().timeIntervalSince(start))
        var tps = (Double(charCount) / 4.0) / elapsed
        var tokenCount = Int(Double(charCount) / 4.0)
        if let ec = finalEvalCount, let ed = finalEvalNs, ed > 0 {
            tps = Double(ec) / (Double(ed) / 1_000_000_000.0)
            tokenCount = ec
        } else if let ec = finalEvalCount {
            tokenCount = ec
        }
        sessions[idx].messages[assistantPos].isStreaming = false
        sessions[idx].messages[assistantPos].tokensPerSecond = tps
        sessions[idx].messages[assistantPos].tokenCount = tokenCount
        sessions[idx].updatedAt = Date()
        liveTokensPerSecond = tps
        _ = assistant
        save()
    }

    /// Retrieve, optionally widening recall with a query-side transform:
    ///  - `.hyde`: append a model-written hypothetical answer to the embedded query.
    ///  - `.multiQuery`: retrieve for a few paraphrases and merge (max score wins).
    /// Both are best-effort; on model failure they degrade to the plain query.
    private func retrieveWithExpansion(baseQuery: String, userText: String, project: Project) async -> [RetrievedChunk] {
        switch settings.queryExpansion {
        case .off:
            return await indexing.retrieve(query: baseQuery, project: project)

        case .hyde:
            let hyde = await inference.complete(
                prompt: "Write a short, factual passage that would directly answer this question. Do not add preamble.\n\nQuestion: \(userText)",
                system: "You draft concise passages for document retrieval.", maxTokens: 160)
            let q = hyde.map { "\(baseQuery)\n\n\($0)" } ?? baseQuery
            return await indexing.retrieve(query: q, project: project)

        case .multiQuery:
            var queries = [baseQuery]
            if let expanded = await inference.complete(
                prompt: "Write 3 alternative phrasings of this question, one per line, no numbering or extra text.\n\nQuestion: \(userText)",
                system: "You rewrite search queries.", maxTokens: 120) {
                queries += expanded.split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .prefix(3)
            }
            var merged: [Int64: RetrievedChunk] = [:]
            for q in queries {
                for c in await indexing.retrieve(query: q, project: project) {
                    if let existing = merged[c.chunkID], existing.score >= c.score { continue }
                    merged[c.chunkID] = c
                }
            }
            return Array(merged.values).sorted { $0.score > $1.score }
                .prefix(settings.retrievalTopK).map { $0 }
        }
    }

    /// Fold the most recent prior user turns into the retrieval query so follow-ups
    /// ("tell me more", "what about its performance?") keep their referent and pull
    /// the right sources. `messages` already includes the current user turn.
    static func retrievalQuery(messages: [ChatMessage], current: String, turns: Int) -> String {
        guard turns > 0 else { return current }
        let priorUsers = messages.filter { $0.role == .user }.dropLast()  // exclude the current turn
        let context = priorUsers.suffix(turns).map { $0.text }
        return (context + [current]).joined(separator: "\n")
    }

    static func buildContext(_ chunks: [RetrievedChunk]) -> String {
        chunks.enumerated().map { i, c in
            let title = c.heading.map { "\(c.fileName) — \($0)" } ?? c.fileName
            return "[\(i + 1)] (\(title))\n\(c.text)"
        }.joined(separator: "\n\n---\n\n")
    }

    // MARK: - Persistence

    private func load() {
        if let data = try? Data(contentsOf: AppPaths.sessionsFile),
           let decoded = try? JSONDecoder().decode([ChatSession].self, from: data) {
            sessions = decoded.sorted { $0.updatedAt > $1.updatedAt }
            currentSessionID = sessions.first?.id
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(sessions) {
            try? data.write(to: AppPaths.sessionsFile, options: .atomic)
        }
    }
}
