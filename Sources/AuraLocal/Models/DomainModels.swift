import Foundation

// MARK: - Inference provider kinds

enum ProviderKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case ollama
    case lmstudio

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .lmstudio: return "LM Studio"
        }
    }
    var defaultBaseURL: String {
        switch self {
        case .ollama: return "http://localhost:11434"
        case .lmstudio: return "http://localhost:1234"
        }
    }
}

// MARK: - Models exposed by a connector

/// What a model is for. Resolved from LM Studio's `/api/v0/models` `type` field
/// when available, otherwise inferred from the name.
enum ModelType: String, Codable, Hashable {
    case chat
    case embedding
    case vision
    case unknown
}

struct ModelInfo: Identifiable, Hashable, Codable {
    var id: String { provider.rawValue + "/" + name }
    var name: String
    var provider: ProviderKind
    var sizeBytes: Int64?
    var family: String?
    var quantization: String?
    var parameterSize: String?
    /// Authoritative classification (LM Studio `type`) or heuristic inference.
    var type: ModelType = .unknown
    /// Whether the runtime reports this model as currently loaded into memory.
    var loaded: Bool = false
    /// Max context window reported by the runtime, when known.
    var maxContextLength: Int?

    var displaySize: String? {
        guard let sizeBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var isEmbedding: Bool { type == .embedding || (type == .unknown && ModelInfo.looksLikeEmbedding(name)) }

    /// Name-based fallback when the runtime doesn't classify the model.
    static func looksLikeEmbedding(_ name: String) -> Bool {
        let n = name.lowercased()
        let needles = ["embed", "bge", "gte", "e5", "nomic", "minilm", "mxbai", "granite-embedding", "arctic-embed"]
        return needles.contains { n.contains($0) }
    }
}

// MARK: - Embedding runtime readiness

/// Live readiness of the configured embedding model. Surfaced in the UI so the
/// user knows when semantic search is active vs. degraded to keyword search.
enum EmbeddingStatus: Equatable {
    case notConfigured            // no embedding model selected
    case providerOffline          // embedding provider's server not reachable
    case modelNotFound            // configured model isn't in the runtime's catalog
    case notLoaded                // model exists but isn't loaded into memory
    case loading                  // a readiness probe is in flight
    case ready(dim: Int)          // verified: a test embed returned `dim` floats
    case error(String)            // probe failed

    var isReady: Bool { if case .ready = self { return true }; return false }

    /// Short status word for badges.
    var label: String {
        switch self {
        case .notConfigured: return "Not set"
        case .providerOffline: return "Offline"
        case .modelNotFound: return "Missing"
        case .notLoaded: return "Not loaded"
        case .loading: return "Loading…"
        case .ready: return "Ready"
        case .error: return "Error"
        }
    }

    /// Human-readable, actionable message.
    func message(model: String, provider: ProviderKind) -> String {
        switch self {
        case .notConfigured:
            return "No embedding model selected. Pick one in Settings to enable semantic search."
        case .providerOffline:
            return "\(provider.displayName) isn't reachable. Start it to enable semantic search — keyword search is active."
        case .modelNotFound:
            return "Embedding model “\(model)” isn't in \(provider.displayName)'s catalog. Pull/download it, then refresh."
        case .notLoaded:
            return "Embedding model “\(model)” is available but not loaded in \(provider.displayName). Load it to enable semantic search — keyword search is active."
        case .loading:
            return "Checking embedding model “\(model)”…"
        case .ready(let dim):
            return "Embedding model “\(model)” ready (\(dim)-dim)."
        case .error(let msg):
            return "Embedding error: \(msg). Keyword search is active."
        }
    }
}

// MARK: - Chat

enum MessageRole: String, Codable { case system, user, assistant }

struct Citation: Identifiable, Hashable, Codable {
    var id = UUID()
    var fileName: String
    /// Path relative to the vault root (matches the DB's stored path).
    var filePath: String
    /// Which vault this source came from — lets us open the file straight from the
    /// chat (even from an old session after the selected vault changed). Optional so
    /// sessions saved before this field decode cleanly (they fall back to the
    /// currently selected vault).
    var projectID: UUID? = nil
    var heading: String?
    var snippet: String
    var score: Double
    /// Set once the answer has streamed: true when the response actually referenced
    /// this file (by bracketed title or file name). Drives the "cited in this answer"
    /// highlight. Optional so sessions saved before v4 decode cleanly.
    var usedInAnswer: Bool? = nil
}

struct ChatMessage: Identifiable, Hashable, Codable {
    var id = UUID()
    var role: MessageRole
    var text: String
    var createdAt: Date = Date()
    var citations: [Citation] = []
    // Generation telemetry
    var tokensPerSecond: Double? = nil
    var tokenCount: Int? = nil
    var modelName: String? = nil
    var isStreaming: Bool = false
}

struct ChatSession: Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String
    var messages: [ChatMessage] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var projectID: UUID? = nil

    var subtitle: String {
        messages.last(where: { $0.role == .user })?.text.prefix(60).description ?? "New conversation"
    }
}

// MARK: - Projects / Vaults

enum VaultKind: String, Codable {
    case obsidian
    case folder
}

/// How a vault is vectorized. As of v2 the app always uses **Full Embed**: every
/// chunk is embedded up-front so queries only embed the query string. The `.smart`
/// case is retained solely so older saved projects/settings decode cleanly and are
/// transparently upgraded to Full Embed.
enum IndexMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case smart
    case full
    var id: String { rawValue }
    var displayName: String { "Full Embed" }
    var blurb: String { "Embed the entire vault up-front. Fastest, most consistent queries." }
}

enum IndexStatus: String, Codable {
    case pending
    case indexing
    case synced
    case error
    case excluded
}

struct IndexedFile: Identifiable, Hashable, Codable {
    var id = UUID()
    var projectID: UUID
    var relativePath: String
    var fileName: String
    var ext: String
    var byteSize: Int64
    var modifiedAt: Date
    var chunkCount: Int = 0
    var embeddedChunkCount: Int = 0
    var tokenEstimate: Int = 0
    var status: IndexStatus = .pending
    var tags: [String] = []
    var aliases: [String] = []
    var lastIndexedAt: Date? = nil
    var embedModel: String = ""
    /// Why this file failed to index (nil when healthy) — drives the Issues list.
    var errorMessage: String? = nil
    /// Display title extracted from the document (falls back to the file name).
    var title: String? = nil

    var hasIssue: Bool { status == .error || (errorMessage?.isEmpty == false) }
}

struct Project: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var kind: VaultKind
    /// Resolved absolute path (for display only — access goes through the bookmark).
    var path: String
    /// base64 security-scoped bookmark data
    var bookmark: Data
    var createdAt: Date = Date()
    var totalTokens: Int = 0
    var indexedFileCount: Int = 0
    var status: IndexStatus = .pending
    var lastEmbeddingAt: Date? = nil

    /// Legacy per-vault vectorization strategy. Kept for decode compatibility only —
    /// v2 always uses Full Embed regardless of the stored value.
    var indexModeRaw: String? = nil
    var indexMode: IndexMode {
        get { .full }
        set { indexModeRaw = newValue.rawValue }
    }
}

// MARK: - Retrieval

struct RetrievedChunk: Identifiable, Hashable {
    var id = UUID()
    var chunkID: Int64
    var fileName: String
    var filePath: String
    var heading: String?
    var text: String
    var score: Double
    var tags: [String]
    var ordinal: Int = 0
}

// MARK: - Telemetry

struct TelemetrySnapshot: Equatable {
    var cpuUsage: Double = 0        // 0...1 (whole machine)
    var memoryUsed: Double = 0      // bytes
    var memoryTotal: Double = 1     // bytes
    var memoryPressure: Double = 0  // 0...1 (unified memory pressure)
    var swapUsed: Double = 0        // bytes
    var appMemory: Double = 0       // bytes (this process — proxy for model "VRAM")
    var coreCount: Int = 1
    var history: [Double] = []      // recent cpu samples for sparkline
    var memHistory: [Double] = []   // recent memory-used fractions (0...1)

    var memoryFraction: Double { memoryTotal > 0 ? memoryUsed / memoryTotal : 0 }
}
