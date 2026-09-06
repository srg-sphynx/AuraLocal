//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import Foundation

/// Generation parameters passed to a connector for a single completion.
struct GenerationConfig {
    var model: String
    var systemPrompt: String
    var temperature: Double
    var topP: Double
    var contextLength: Int
    var maxTokens: Int
}

/// A single streamed delta from the model.
struct StreamToken {
    var text: String
    var done: Bool
    /// Provider-reported eval stats (Ollama supplies these on the final frame).
    var evalCount: Int? = nil
    var evalDurationNs: Int64? = nil
}

enum InferenceError: LocalizedError {
    case badURL(String)
    case http(Int, String)
    case decode(String)
    case notReachable(String)

    var errorDescription: String? {
        switch self {
        case .badURL(let s): return "Invalid endpoint URL: \(s)"
        case .http(let code, let body): return "HTTP \(code): \(body)"
        case .decode(let s): return "Failed to decode response: \(s)"
        case .notReachable(let s): return "Endpoint not reachable: \(s)"
        }
    }
}

/// Extensible connector abstraction — every local engine implements this.
/// `Sendable` because connectors are immutable value types, so they can be handed
/// to the concurrent embedding task group.
protocol InferenceProvider: Sendable {
    var kind: ProviderKind { get }
    var baseURL: URL { get }
    var apiKey: String { get }

    func listModels() async throws -> [ModelInfo]
    func streamChat(messages: [ChatMessage], config: GenerationConfig) -> AsyncThrowingStream<StreamToken, Error>
    func embed(texts: [String], model: String) async throws -> [[Float]]
    func ping() async -> Bool
}

extension InferenceProvider {
    func authorizedRequest(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        if !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return req
    }
}

/// Factory + helpers shared by connectors.
enum ProviderFactory {
    static func make(_ kind: ProviderKind, settings: AppSettings) -> InferenceProvider {
        let urlString = settings.baseURL(for: kind)
        let url = URL(string: urlString) ?? URL(string: kind.defaultBaseURL)!
        switch kind {
        case .ollama:   return OllamaProvider(baseURL: url, apiKey: settings.apiKey(for: kind))
        case .lmstudio: return LMStudioProvider(baseURL: url, apiKey: settings.apiKey(for: kind))
        }
    }
}
