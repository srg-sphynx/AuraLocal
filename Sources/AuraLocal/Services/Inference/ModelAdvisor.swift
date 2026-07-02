import Foundation

/// Offline, model-aware configuration advisor.
///
/// Recommends a chat model, an embedding model, a context length, and a chunk
/// size based on the models actually installed plus available system RAM. The
/// knowledge below is a curated snapshot of common local models (mid-2026); it is
/// intentionally static so the app stays fully offline.
///
/// Sources (captured in the plan): LM Studio "Best Local Models for RAG 2026",
/// Morph "Ollama Embedding Models 2026", Ollama model library.
enum ModelAdvisor {

    // MARK: - Knowledge base

    struct EmbeddingSpec {
        let key: String            // lowercased substring to match an installed model name
        let display: String
        let dim: Int
        let maxContext: Int
        let recommendedChunkTokens: Int
        let priority: Int          // higher = preferred when several are installed
        let pull: String           // `ollama pull` name / LM Studio search term
        let blurb: String
    }

    struct ChatSpec {
        let key: String
        let display: String
        let approxParamsB: Double
        let minRAMGB: Double       // comfortable floor for this model
        let defaultContext: Int
        let pull: String
        let blurb: String
    }

    /// Ordered by preference within each capability tier.
    static let embeddings: [EmbeddingSpec] = [
        .init(key: "bge-m3", display: "bge-m3", dim: 1024, maxContext: 8192, recommendedChunkTokens: 900, priority: 95,
              pull: "bge-m3", blurb: "Multilingual, long 8K context — great for mixed vaults."),
        .init(key: "qwen3-embedding", display: "qwen3-embedding:0.6b", dim: 1024, maxContext: 32768, recommendedChunkTokens: 1000, priority: 92,
              pull: "qwen3-embedding:0.6b", blurb: "Top sub-1GB model, 32K context."),
        .init(key: "nomic-embed-text", display: "nomic-embed-text", dim: 768, maxContext: 2048, recommendedChunkTokens: 512, priority: 88,
              pull: "nomic-embed-text", blurb: "The reliable default — small, fast, Apache-2.0."),
        .init(key: "embeddinggemma", display: "embeddinggemma", dim: 768, maxContext: 2048, recommendedChunkTokens: 512, priority: 86,
              pull: "embeddinggemma", blurb: "Google Gemma embeddings, Matryoshka-truncatable."),
        .init(key: "snowflake-arctic-embed", display: "snowflake-arctic-embed2", dim: 1024, maxContext: 8192, recommendedChunkTokens: 800, priority: 80,
              pull: "snowflake-arctic-embed2", blurb: "Strong retrieval quality, long context."),
        .init(key: "mxbai-embed-large", display: "mxbai-embed-large", dim: 1024, maxContext: 512, recommendedChunkTokens: 384, priority: 70,
              pull: "mxbai-embed-large", blurb: "High quality but short 512-token window — use smaller chunks."),
        .init(key: "granite-embedding", display: "granite-embedding", dim: 384, maxContext: 512, recommendedChunkTokens: 384, priority: 60,
              pull: "granite-embedding", blurb: "IBM Granite — compact and efficient."),
        .init(key: "all-minilm", display: "all-minilm", dim: 384, maxContext: 256, recommendedChunkTokens: 256, priority: 40,
              pull: "all-minilm", blurb: "Tiny & fast; lower accuracy — keep chunks short."),
    ]

    static let chats: [ChatSpec] = [
        .init(key: "gemma3:27b", display: "gemma3:27b", approxParamsB: 27, minRAMGB: 48, defaultContext: 8192, pull: "gemma3:27b", blurb: "Flagship Gemma 3 — needs a lot of RAM."),
        .init(key: "qwen2.5:32b", display: "qwen2.5:32b", approxParamsB: 32, minRAMGB: 48, defaultContext: 16384, pull: "qwen2.5:32b", blurb: "Very capable, long context."),
        .init(key: "gemma3:12b", display: "gemma3:12b", approxParamsB: 12, minRAMGB: 24, defaultContext: 8192, pull: "gemma3:12b", blurb: "Excellent quality/size balance."),
        .init(key: "phi4", display: "phi4", approxParamsB: 14, minRAMGB: 24, defaultContext: 16384, pull: "phi4", blurb: "Microsoft Phi-4 — strong reasoning for its size."),
        .init(key: "qwen2.5:14b", display: "qwen2.5:14b", approxParamsB: 14, minRAMGB: 24, defaultContext: 16384, pull: "qwen2.5:14b", blurb: "Great all-rounder."),
        .init(key: "gemma3:4b", display: "gemma3:4b", approxParamsB: 4, minRAMGB: 12, defaultContext: 8192, pull: "gemma3:4b", blurb: "Best default for 16GB machines."),
        .init(key: "llama3.1:8b", display: "llama3.1:8b", approxParamsB: 8, minRAMGB: 16, defaultContext: 8192, pull: "llama3.1:8b", blurb: "Dependable general model."),
        .init(key: "qwen2.5:7b", display: "qwen2.5:7b", approxParamsB: 7, minRAMGB: 14, defaultContext: 16384, pull: "qwen2.5:7b", blurb: "Strong 7B with long context."),
        .init(key: "llama3.2:3b", display: "llama3.2:3b", approxParamsB: 3, minRAMGB: 8, defaultContext: 8192, pull: "llama3.2:3b", blurb: "Runs comfortably on light hardware."),
        .init(key: "gemma3:1b", display: "gemma3:1b", approxParamsB: 1, minRAMGB: 6, defaultContext: 8192, pull: "gemma3:1b", blurb: "Ultra-light fallback."),
    ]

    // MARK: - Recommendation

    struct Recommendation {
        var chatModel: ModelInfo?           // installed pick (if any)
        var chatSuggestion: ChatSpec?       // download suggestion when nothing suitable is installed
        var embeddingModel: ModelInfo?      // installed pick (if any)
        var embeddingSuggestion: EmbeddingSpec?
        var contextLength: Int
        var chunkTokens: Int
        var notes: [String]

        var chatLabel: String { chatModel?.name ?? chatSuggestion?.display ?? "—" }
        var embeddingLabel: String { embeddingModel?.name ?? embeddingSuggestion?.display ?? "—" }
    }

    static func spec(forEmbeddingName name: String) -> EmbeddingSpec? {
        let n = name.lowercased()
        return embeddings.first { n.contains($0.key) }
    }

    static func recommend(installed: [ModelInfo], ramGB: Double) -> Recommendation {
        var notes: [String] = []

        // --- Chat model: largest installed that comfortably fits RAM, else suggest. ---
        let installedChats = installed.filter { !$0.isEmbedding }
        let scoredChats: [(ModelInfo, ChatSpec)] = installedChats.compactMap { m in
            let n = m.name.lowercased()
            guard let spec = chats.first(where: { n.contains($0.key) }) else { return nil }
            return (m, spec)
        }.filter { $0.1.minRAMGB <= ramGB + 0.5 }   // tolerate near-fits

        var chatModel: ModelInfo?
        var chatSuggestion: ChatSpec?
        var contextLength = 8192
        if let best = scoredChats.max(by: { $0.1.approxParamsB < $1.1.approxParamsB }) {
            chatModel = best.0
            contextLength = best.0.maxContextLength.map { min($0, recommendedCtx(ramGB)) } ?? best.1.defaultContext
        } else if let firstUnknown = installedChats.first {
            // An installed chat model we don't have a spec for — still usable.
            chatModel = firstUnknown
            contextLength = firstUnknown.maxContextLength.map { min($0, recommendedCtx(ramGB)) } ?? recommendedCtx(ramGB)
            notes.append("Using installed “\(firstUnknown.name)” (no preset — context defaulted to \(contextLength)).")
        } else {
            chatSuggestion = chats.first { $0.minRAMGB <= ramGB } ?? chats.last
            contextLength = chatSuggestion?.defaultContext ?? 8192
            if let s = chatSuggestion { notes.append("No chat model installed — pull `\(s.pull)`.") }
        }

        // --- Embedding model: best installed by priority, else suggest nomic. ---
        let installedEmb = installed.filter { $0.isEmbedding }
        let scoredEmb: [(ModelInfo, EmbeddingSpec)] = installedEmb.compactMap { m in
            spec(forEmbeddingName: m.name).map { (m, $0) }
        }
        var embeddingModel: ModelInfo?
        var embeddingSuggestion: EmbeddingSpec?
        var chunkTokens = 512
        if let best = scoredEmb.max(by: { $0.1.priority < $1.1.priority }) {
            embeddingModel = best.0
            chunkTokens = best.1.recommendedChunkTokens
            if best.1.maxContext <= 512 {
                notes.append("“\(best.1.display)” has a short \(best.1.maxContext)-token window — chunk size set to \(chunkTokens).")
            }
        } else if let firstUnknown = installedEmb.first {
            embeddingModel = firstUnknown
            notes.append("Using installed embedding model “\(firstUnknown.name)”.")
        } else {
            embeddingSuggestion = embeddings.first { $0.key == "nomic-embed-text" }
            chunkTokens = embeddingSuggestion?.recommendedChunkTokens ?? 512
            notes.append("No embedding model installed — pull `\(embeddingSuggestion?.pull ?? "nomic-embed-text")` to enable semantic search.")
        }

        notes.append("Tuned for ~\(Int(ramGB.rounded())) GB RAM.")
        return Recommendation(chatModel: chatModel, chatSuggestion: chatSuggestion,
                              embeddingModel: embeddingModel, embeddingSuggestion: embeddingSuggestion,
                              contextLength: contextLength, chunkTokens: chunkTokens, notes: notes)
    }

    private static func recommendedCtx(_ ramGB: Double) -> Int {
        switch ramGB {
        case ..<10:  return 4096
        case ..<20:  return 8192
        case ..<40:  return 16384
        default:     return 32768
        }
    }

    /// Apply a recommendation's installed picks + tuning to settings (one-click).
    static func apply(_ rec: Recommendation, to settings: inout AppSettings) {
        if let chat = rec.chatModel {
            settings.activeProvider = chat.provider
            settings.activeChatModel = chat.name
        }
        if let emb = rec.embeddingModel {
            settings.embeddingProvider = emb.provider
            settings.embeddingModel = emb.name
        } else if let sug = rec.embeddingSuggestion {
            settings.embeddingModel = sug.pull
        }
        settings.contextLength = rec.contextLength
        settings.chunkMaxTokens = rec.chunkTokens
    }
}
