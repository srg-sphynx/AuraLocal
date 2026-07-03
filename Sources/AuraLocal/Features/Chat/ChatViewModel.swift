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
    private func index(of sessionID: UUID) -> Int? {
        sessions.firstIndex { $0.id == sessionID }
    }
    /// Re-resolve a specific message inside a specific session. Indices are looked up
    /// fresh on every write because starting a new chat inserts at index 0 and shifts
    /// every session's position — a captured index would otherwise stream tokens into
    /// the wrong conversation.
    private func locate(_ sessionID: UUID, _ messageID: UUID) -> (s: Int, m: Int)? {
        guard let s = sessions.firstIndex(where: { $0.id == sessionID }),
              let m = sessions[s].messages.firstIndex(where: { $0.id == messageID }) else { return nil }
        return (s, m)
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
        indexing.resetSessionCache(id)
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
        guard !text.isEmpty, !isGenerating,
              let sessionID = currentSessionID, let idx = index(of: sessionID) else { return }
        draft = ""

        sessions[idx].messages.append(ChatMessage(role: .user, text: text))
        if sessions[idx].title == "New Chat" {
            sessions[idx].title = String(text.prefix(40))
        }
        sessions[idx].updatedAt = Date()

        streamTask = Task { await runCompletion(sessionID: sessionID, userText: text) }
    }

    private func runCompletion(sessionID: UUID, userText: String) async {
        guard let turnIdx = index(of: sessionID) else { return }
        isGenerating = true
        liveTokensPerSecond = 0
        defer { isGenerating = false }

        // 1. Assistant placeholder appears IMMEDIATELY — before retrieval — so a slow
        //    first query (a cold or bulk-saturated embed server right after indexing a
        //    new vault) shows a "Thinking…" bubble instead of looking like the message
        //    did nothing. `priorMessages` is captured before the placeholder so it never
        //    leaks the empty assistant turn into the model prompt or the retrieval query.
        let priorMessages = sessions[turnIdx].messages.filter { $0.role != .system }
        let assistant = ChatMessage(role: .assistant, text: "",
                                    modelName: settings.activeChatModel, isStreaming: true)
        let assistantID = assistant.id
        sessions[turnIdx].messages.append(assistant)

        // 2. Retrieval (RAG). The query embed is bounded (see IndexingService) so a
        //    stalled embed server degrades to keyword search rather than hanging.
        var citations: [Citation] = []
        var contextBlock = ""
        if ragEnabled, let project = projects.selectedProject {
            lastRetrievalQuery = userText
            let retrievalQuery = Self.retrievalQuery(messages: priorMessages,
                                                     current: userText,
                                                     turns: settings.historyTurnsForRetrieval)
            let chunks = await retrieveWithExpansion(baseQuery: retrievalQuery, userText: userText,
                                                     project: project, session: sessionID)
            lastRetrieval = chunks
            if !chunks.isEmpty {
                contextBlock = Self.buildContext(chunks)
                citations = Self.fileLevelCitations(chunks, projectID: project.id)
            }
        } else {
            lastRetrieval = []
        }
        if let loc = locate(sessionID, assistantID) {
            sessions[loc.s].messages[loc.m].citations = citations
        }

        // 3. Compose message history (+ context preamble on the latest user turn). Built
        //    from `priorMessages`, so the streaming assistant placeholder is excluded.
        var history = priorMessages
        if !contextBlock.isEmpty, let lastUser = history.lastIndex(where: { $0.role == .user }) {
            history[lastUser].text = """
            Use the following context from my vault to answer. Cite note titles in brackets.

            <context>
            \(contextBlock)
            </context>

            Question: \(userText)
            """
        }

        // 4. Stream
        let provider = inference.activeProvider
        let config = GenerationConfig(model: settings.activeChatModel,
                                      systemPrompt: settings.systemPrompt,
                                      temperature: settings.temperature,
                                      topP: settings.topP,
                                      contextLength: settings.contextLength,
                                      maxTokens: settings.maxTokens)

        guard !settings.activeChatModel.isEmpty else {
            if let loc = locate(sessionID, assistantID) {
                sessions[loc.s].messages[loc.m].text = "⚠️ No model selected. Open **Model Zoo** or **Settings** to choose a local model."
                sessions[loc.s].messages[loc.m].isStreaming = false
            }
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
                    if let loc = locate(sessionID, assistantID) {
                        sessions[loc.s].messages[loc.m].text += token.text
                    }
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
            if let loc = locate(sessionID, assistantID) {
                sessions[loc.s].messages[loc.m].text += "\n\n⚠️ \(error.localizedDescription)"
            }
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
        if let loc = locate(sessionID, assistantID) {
            sessions[loc.s].messages[loc.m].isStreaming = false
            sessions[loc.s].messages[loc.m].tokensPerSecond = tps
            sessions[loc.s].messages[loc.m].tokenCount = tokenCount
            // Now the answer text is final: flag which sources it actually referenced and
            // float those to the front, so the strip highlights the files behind THIS answer.
            let answer = sessions[loc.s].messages[loc.m].text
            sessions[loc.s].messages[loc.m].citations =
                Self.markAnswerCitations(sessions[loc.s].messages[loc.m].citations, answer: answer)
            sessions[loc.s].updatedAt = Date()
        }
        liveTokensPerSecond = tps
        save()
    }

    /// Retrieve, optionally widening recall with a query-side transform:
    ///  - `.hyde`: append a model-written hypothetical answer to the embedded query.
    ///  - `.multiQuery`: retrieve for a few paraphrases and merge (max score wins).
    /// Both are best-effort; on model failure they degrade to the plain query.
    private func retrieveWithExpansion(baseQuery: String, userText: String,
                                       project: Project, session: UUID?) async -> [RetrievedChunk] {
        switch settings.queryExpansion {
        case .off:
            return await indexing.retrieve(query: baseQuery, project: project, session: session)

        case .hyde:
            let hyde = await inference.complete(
                prompt: "Write a short, factual passage that would directly answer this question. Do not add preamble.\n\nQuestion: \(userText)",
                system: "You draft concise passages for document retrieval.", maxTokens: 160)
            let q = hyde.map { "\(baseQuery)\n\n\($0)" } ?? baseQuery
            return await indexing.retrieve(query: q, project: project, session: session)

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
                for c in await indexing.retrieve(query: q, project: project, session: session) {
                    if let existing = merged[c.chunkID], existing.score >= c.score { continue }
                    merged[c.chunkID] = c
                }
            }
            return Array(merged.values).sorted { $0.score > $1.score }
                .prefix(settings.retrievalTopK).map { $0 }
        }
    }

    /// Collapse the retrieved chunks to one citation per **file** (best-scoring chunk
    /// wins), so the "Relevant files" strip lists distinct sources — not the same note
    /// three times. Chunks arrive in rank order, so the first seen per file is its best.
    static func fileLevelCitations(_ chunks: [RetrievedChunk], projectID: UUID) -> [Citation] {
        var seen = Set<String>()
        var out: [Citation] = []
        for c in chunks where seen.insert(c.filePath).inserted {
            out.append(Citation(fileName: c.fileName, filePath: c.filePath, projectID: projectID,
                                 heading: c.heading, snippet: String(c.text.prefix(220)), score: c.score))
        }
        return out
    }

    /// After the answer streams, flag which cited files the response actually referenced
    /// (the model is asked to cite note titles), and float those to the front. If nothing
    /// was referenced explicitly, the retrieval (score) order is kept.
    static func markAnswerCitations(_ citations: [Citation], answer: String) -> [Citation] {
        guard !citations.isEmpty, !answer.isEmpty else { return citations }
        let haystack = answer.lowercased()
        var marked = citations.map { c -> Citation in
            var c = c
            let base = (c.fileName as NSString).deletingPathExtension.lowercased()
            let headHit = c.heading.map { $0.count >= 4 && haystack.contains($0.lowercased()) } ?? false
            c.usedInAnswer = (base.count >= 3 && haystack.contains(base)) || headHit
            return c
        }
        if marked.contains(where: { $0.usedInAnswer == true }) {
            marked.sort { a, b in
                let ua = (a.usedInAnswer == true), ub = (b.usedInAnswer == true)
                return ua == ub ? a.score > b.score : ua
            }
        }
        return marked
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
