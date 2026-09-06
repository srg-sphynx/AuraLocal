//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import Foundation

/// All user-configurable settings, persisted as JSON in Application Support.
///
/// NOTE: a hand-written `init(from:)` (see extension below) decodes every field
/// with `decodeIfPresent ?? default`, so adding new settings never wipes a user's
/// existing `settings.json` on upgrade.
struct AppSettings: Codable, Equatable {

    // MARK: Connections
    var ollamaBaseURL: String = ProviderKind.ollama.defaultBaseURL
    var lmStudioBaseURL: String = ProviderKind.lmstudio.defaultBaseURL
    var ollamaAPIKey: String = ""
    var lmStudioAPIKey: String = ""

    // MARK: Active model configuration
    // Default split: LM Studio drives the chat LLM; Ollama drives embeddings.
    var activeProvider: ProviderKind = .lmstudio
    var activeChatModel: String = ""
    var embeddingProvider: ProviderKind = .ollama
    var embeddingModel: String = "bge-m3"

    // MARK: Generation parameters
    var temperature: Double = 0.7
    var topP: Double = 0.9
    var contextLength: Int = 8192
    var maxTokens: Int = 2048
    var systemPrompt: String =
        "You are Aura, a precise local assistant. Answer using the provided context from the user's vault when relevant. Cite note titles. If the context does not contain the answer, say so."

    // MARK: RAG parameters
    var retrievalTopK: Int = 6
    var minSimilarity: Double = 0.0
    var chunkMaxTokens: Int = 512
    var chunkOverlap: Int = 64
    var ragEnabledByDefault: Bool = true
    var rerankEnabled: Bool = true
    var autoRefreshOnSave: Bool = true

    /// Legacy default vectorization strategy. v2 always uses Full Embed; kept for
    /// settings.json decode compatibility only.
    var indexModeDefault: IndexMode = .full
    /// Keyword arm: how many top files (by BM25 score) to pull chunks from per query.
    var candidateFileWindow: Int = 20
    /// Semantic arm: how many chunks the pure-cosine scan contributes as candidates.
    var semanticCandidateCount: Int = 200
    /// How many recent user turns to fold into the retrieval query so follow-ups
    /// ("tell me more", "what about it") resolve their referents.
    var historyTurnsForRetrieval: Int = 2
    /// Hybrid re-rank weighting: 0 = pure keyword (BM25), 1 = pure semantic (cosine).
    /// Retained as a soft bias knob; v3 fuses ranks with RRF (see `rerankMode`).
    var rerankWeight: Double = 0.6
    /// Embedding throughput controls (used by the up-front full embedding pass).
    var embeddingBatchSize: Int = 16
    var embeddingConcurrency: Int = 3

    // MARK: RAG v3 — retrieval intelligence
    /// Use the on-disk ANN (HNSW) index for semantic recall instead of the exact
    /// O(N) cosine scan. Falls back to the exact scan automatically when the index
    /// is missing/stale or the vault is small.
    var annEnabled: Bool = true
    /// After top-K selection, pull adjacent chunks (same file, neighboring ordinals)
    /// into the LLM context for coherence ("small-to-big" / parent-document).
    var parentExpansion: Bool = true
    /// How final candidates are ordered. `hybridRRF` is the parameter-free default.
    var rerankMode: RerankMode = .hybridRRF
    /// Optional query-side transform to widen recall on reworded questions.
    var queryExpansion: QueryExpansion = .off
    /// OCR scanned PDF pages that yield no extractable text (slow; off by default).
    var pdfOCRFallback: Bool = false
    /// Skip (with a logged warning) any single file larger than this many MB.
    var maxFileSizeMB: Int = 32
    /// One-time flag: on first v3 launch we merge the newly supported formats into
    /// the user's `includedExtensions` so upgrades gain HTML/DOCX/EPUB/… automatically.
    var formatsUpgradedV3: Bool = false

    // MARK: RAG v4 — adaptive source cache
    /// Keep a per-chat working set of the sources already retrieved so follow-up
    /// questions that stay within that material are answered WITHOUT re-scanning the
    /// whole vector store. Purely additive speed: a question that drifts to new files
    /// always falls back to a full vault scan and merges the new sources in.
    var adaptiveSourceCache: Bool = true
    /// Minimum best-cosine a query must reach against the cached working set to be
    /// answered from cache (the "fast path"). Below this the full vault is re-scanned.
    var adaptiveReuseThreshold: Double = 0.60

    // MARK: Onboarding
    var hasCompletedOnboarding: Bool = false
    var onboardingVersion: Int = 0
    /// Last app version whose "What's New" the user has seen. Drives the one-time
    /// post-update changelog popup (see `RootView`). Empty on a fresh install.
    var lastSeenVersion: String = ""

    // MARK: Storage / indexing rules
    var excludedPatterns: [String] = [
        ".obsidian", ".trash", ".git", "node_modules",
        "*.png", "*.jpg", "*.jpeg", "*.gif", "*.svg", "*.webp",
        "*.mp4", "*.mov", "*.mp3", "*.wav", "*.zip", "*.excalidraw"
    ]
    var includedExtensions: [String] = SupportedFormats.defaultIncludedExtensions
    var vectorStorePath: String = ""  // empty -> default Application Support location

    // MARK: Appearance / theming
    var theme: ThemeConfig = ThemeConfig()
}

// MARK: - Forward/backward-compatible decoding

extension AppSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()  // defaults source
        func s<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) .flatMap { $0 } ?? fallback
        }
        ollamaBaseURL    = s(.ollamaBaseURL, d.ollamaBaseURL)
        lmStudioBaseURL  = s(.lmStudioBaseURL, d.lmStudioBaseURL)
        ollamaAPIKey     = s(.ollamaAPIKey, d.ollamaAPIKey)
        lmStudioAPIKey   = s(.lmStudioAPIKey, d.lmStudioAPIKey)
        activeProvider   = s(.activeProvider, d.activeProvider)
        activeChatModel  = s(.activeChatModel, d.activeChatModel)
        embeddingProvider = s(.embeddingProvider, d.embeddingProvider)
        embeddingModel   = s(.embeddingModel, d.embeddingModel)
        temperature      = s(.temperature, d.temperature)
        topP             = s(.topP, d.topP)
        contextLength    = s(.contextLength, d.contextLength)
        maxTokens        = s(.maxTokens, d.maxTokens)
        systemPrompt     = s(.systemPrompt, d.systemPrompt)
        retrievalTopK    = s(.retrievalTopK, d.retrievalTopK)
        minSimilarity    = s(.minSimilarity, d.minSimilarity)
        chunkMaxTokens   = s(.chunkMaxTokens, d.chunkMaxTokens)
        chunkOverlap     = s(.chunkOverlap, d.chunkOverlap)
        ragEnabledByDefault = s(.ragEnabledByDefault, d.ragEnabledByDefault)
        rerankEnabled    = s(.rerankEnabled, d.rerankEnabled)
        autoRefreshOnSave = s(.autoRefreshOnSave, d.autoRefreshOnSave)
        indexModeDefault = s(.indexModeDefault, d.indexModeDefault)
        candidateFileWindow = s(.candidateFileWindow, d.candidateFileWindow)
        semanticCandidateCount = s(.semanticCandidateCount, d.semanticCandidateCount)
        historyTurnsForRetrieval = s(.historyTurnsForRetrieval, d.historyTurnsForRetrieval)
        rerankWeight     = s(.rerankWeight, d.rerankWeight)
        embeddingBatchSize = s(.embeddingBatchSize, d.embeddingBatchSize)
        embeddingConcurrency = s(.embeddingConcurrency, d.embeddingConcurrency)
        annEnabled       = s(.annEnabled, d.annEnabled)
        parentExpansion  = s(.parentExpansion, d.parentExpansion)
        rerankMode       = s(.rerankMode, d.rerankMode)
        queryExpansion   = s(.queryExpansion, d.queryExpansion)
        pdfOCRFallback   = s(.pdfOCRFallback, d.pdfOCRFallback)
        maxFileSizeMB    = s(.maxFileSizeMB, d.maxFileSizeMB)
        formatsUpgradedV3 = s(.formatsUpgradedV3, d.formatsUpgradedV3)
        adaptiveSourceCache = s(.adaptiveSourceCache, d.adaptiveSourceCache)
        adaptiveReuseThreshold = s(.adaptiveReuseThreshold, d.adaptiveReuseThreshold)
        hasCompletedOnboarding = s(.hasCompletedOnboarding, d.hasCompletedOnboarding)
        onboardingVersion = s(.onboardingVersion, d.onboardingVersion)
        lastSeenVersion = s(.lastSeenVersion, d.lastSeenVersion)
        excludedPatterns = s(.excludedPatterns, d.excludedPatterns)
        includedExtensions = s(.includedExtensions, d.includedExtensions)
        vectorStorePath  = s(.vectorStorePath, d.vectorStorePath)
        theme            = s(.theme, d.theme)
    }
}

// MARK: - Retrieval configuration

/// How final retrieval candidates are ordered.
enum RerankMode: String, Codable, CaseIterable, Identifiable {
    case off          // pure semantic (cosine/ANN) order
    case hybridRRF    // Reciprocal Rank Fusion of BM25 + semantic (default)
    case llmJudge     // RRF, then re-scored by the local chat model

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .off:       return "Semantic only"
        case .hybridRRF: return "Hybrid (RRF)"
        case .llmJudge:  return "LLM re-rank"
        }
    }
    var blurb: String {
        switch self {
        case .off:       return "Order purely by vector similarity."
        case .hybridRRF: return "Fuse keyword + semantic ranks. Fast, robust, recommended."
        case .llmJudge:  return "Have the chat model re-score top hits. Highest quality, slower."
        }
    }
}

/// Optional query-side transform applied before retrieval.
enum QueryExpansion: String, Codable, CaseIterable, Identifiable {
    case off
    case multiQuery   // LLM writes paraphrases; union their retrievals
    case hyde         // LLM writes a hypothetical answer; embed that

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .off:        return "Off"
        case .multiQuery: return "Multi-query"
        case .hyde:       return "HyDE"
        }
    }
    var blurb: String {
        switch self {
        case .off:        return "Retrieve on the question as written."
        case .multiQuery: return "Generate paraphrases and merge their hits. Wider recall, slower."
        case .hyde:       return "Embed a hypothetical answer for closer matches. Slower."
        }
    }
}

// MARK: - Theme configuration

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum ThemeDensity: String, Codable, CaseIterable, Identifiable {
    case compact, comfortable
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    /// Multiplier applied to vertical paddings / control sizing.
    var scale: CGFloat { self == .compact ? 0.82 : 1.0 }
}

/// A saved custom theme. Only the accent is required; the rest fall back to the
/// base (light/dark) palette so a preset is a light touch on top of the base.
struct ThemePreset: Codable, Equatable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = "Custom"
    var basedOnDark: Bool = true
    var accentHex: UInt32 = 0x5E5CE6
    var surfaceHex: UInt32? = nil
    var onSurfaceHex: UInt32? = nil
    var successHex: UInt32? = nil
}

struct ThemeConfig: Codable, Equatable {
    var mode: AppearanceMode = .dark
    var accentHex: UInt32 = 0x5E5CE6     // default indigo (matches legacy primaryVivid)
    var highContrast: Bool = false
    var density: ThemeDensity = .comfortable
    /// Legacy manual text scale — retained for decode compatibility only. Text size
    /// now tracks the system setting automatically (see `ThemeManager.systemFontScale`).
    var fontScale: Double = 1.0
    /// Glass transparency: 0 = solid panes, 1 = mostly the blurred wallpaper.
    var glassTransparency: Double = 0.4
    var customThemes: [ThemePreset] = []
    var activePresetID: UUID? = nil

    var activePreset: ThemePreset? {
        guard let id = activePresetID else { return nil }
        return customThemes.first { $0.id == id }
    }

    /// Field-tolerant decoding so adding theme options never resets a saved theme.
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ThemeConfig()
        mode = (try? c.decodeIfPresent(AppearanceMode.self, forKey: .mode)) .flatMap { $0 } ?? d.mode
        accentHex = (try? c.decodeIfPresent(UInt32.self, forKey: .accentHex)) .flatMap { $0 } ?? d.accentHex
        highContrast = (try? c.decodeIfPresent(Bool.self, forKey: .highContrast)) .flatMap { $0 } ?? d.highContrast
        density = (try? c.decodeIfPresent(ThemeDensity.self, forKey: .density)) .flatMap { $0 } ?? d.density
        fontScale = (try? c.decodeIfPresent(Double.self, forKey: .fontScale)) .flatMap { $0 } ?? d.fontScale
        glassTransparency = (try? c.decodeIfPresent(Double.self, forKey: .glassTransparency)) .flatMap { $0 } ?? d.glassTransparency
        customThemes = (try? c.decodeIfPresent([ThemePreset].self, forKey: .customThemes)) .flatMap { $0 } ?? d.customThemes
        activePresetID = (try? c.decodeIfPresent(UUID.self, forKey: .activePresetID)) .flatMap { $0 } ?? d.activePresetID
    }
}

extension AppSettings {
    func baseURL(for provider: ProviderKind) -> String {
        switch provider {
        case .ollama: return ollamaBaseURL
        case .lmstudio: return lmStudioBaseURL
        }
    }
    func apiKey(for provider: ProviderKind) -> String {
        switch provider {
        case .ollama: return ollamaAPIKey
        case .lmstudio: return lmStudioAPIKey
        }
    }

    /// Identity of the chunking parameters. When this changes, affected files are
    /// re-chunked on the next scan (so chunk-size/overlap edits actually take hold).
    var chunkParamsHash: String { "\(chunkMaxTokens):\(chunkOverlap)" }
}
