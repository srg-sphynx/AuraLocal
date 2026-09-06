//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import Foundation

/// Connector for the Ollama runtime (default http://localhost:11434).
/// Uses the native /api/chat streaming endpoint (newline-delimited JSON).
struct OllamaProvider: InferenceProvider {
    let kind: ProviderKind = .ollama
    let baseURL: URL
    let apiKey: String

    func ping() async -> Bool {
        var req = authorizedRequest(baseURL.appendingPathComponent("api/tags"))
        req.timeoutInterval = 2
        return (try? await URLSession.shared.data(for: req)) != nil
    }

    func listModels() async throws -> [ModelInfo] {
        let url = baseURL.appendingPathComponent("api/tags")
        let (data, resp) = try await URLSession.shared.data(for: authorizedRequest(url))
        try Self.validate(resp, data)
        struct Tags: Decodable {
            struct M: Decodable {
                let name: String
                let size: Int64?
                struct Details: Decodable {
                    let family: String?
                    let parameter_size: String?
                    let quantization_level: String?
                }
                let details: Details?
            }
            let models: [M]
        }
        let decoded = try JSONDecoder().decode(Tags.self, from: data)
        let loaded = await loadedModelNames()
        return decoded.models.map {
            let isEmbed = ModelInfo.looksLikeEmbedding($0.name)
                || ($0.details?.family.map { ModelInfo.looksLikeEmbedding($0) } ?? false)
            return ModelInfo(name: $0.name, provider: .ollama, sizeBytes: $0.size,
                             family: $0.details?.family,
                             quantization: $0.details?.quantization_level,
                             parameterSize: $0.details?.parameter_size,
                             type: isEmbed ? .embedding : .chat,
                             loaded: loaded.contains($0.name))
        }
    }

    /// Models currently resident in memory (Ollama auto-loads on demand, so this
    /// reflects what has been used recently rather than what's available).
    func loadedModelNames() async -> Set<String> {
        var req = authorizedRequest(baseURL.appendingPathComponent("api/ps"))
        req.timeoutInterval = 3
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return [] }
        struct PS: Decodable { struct M: Decodable { let name: String }; let models: [M] }
        guard let decoded = try? JSONDecoder().decode(PS.self, from: data) else { return [] }
        return Set(decoded.models.map { $0.name })
    }

    func streamChat(messages: [ChatMessage], config: GenerationConfig) -> AsyncThrowingStream<StreamToken, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var msgs: [[String: String]] = []
                    if !config.systemPrompt.isEmpty {
                        msgs.append(["role": "system", "content": config.systemPrompt])
                    }
                    for m in messages where m.role != .system {
                        msgs.append(["role": m.role.rawValue, "content": m.text])
                    }
                    let body: [String: Any] = [
                        "model": config.model,
                        "messages": msgs,
                        "stream": true,
                        "options": [
                            "temperature": config.temperature,
                            "top_p": config.topP,
                            "num_ctx": config.contextLength,
                            "num_predict": config.maxTokens
                        ]
                    ]
                    var req = authorizedRequest(baseURL.appendingPathComponent("api/chat"))
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw InferenceError.http(http.statusCode, "ollama chat failed")
                    }
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard let data = line.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        let content = (obj["message"] as? [String: Any])?["content"] as? String ?? ""
                        let done = obj["done"] as? Bool ?? false
                        let evalCount = obj["eval_count"] as? Int
                        let evalDur = (obj["eval_duration"] as? NSNumber)?.int64Value
                        continuation.yield(StreamToken(text: content, done: done,
                                                       evalCount: evalCount, evalDurationNs: evalDur))
                        if done { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func embed(texts: [String], model: String) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        // Modern batch endpoint: one round-trip for the whole batch.
        if let batched = try? await embedBatch(texts: texts, model: model) { return batched }
        // Legacy fallback: per-text /api/embeddings.
        var out: [[Float]] = []
        for text in texts {
            let body: [String: Any] = ["model": model, "prompt": text]
            var req = authorizedRequest(baseURL.appendingPathComponent("api/embeddings"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await URLSession.shared.data(for: req)
            try Self.validate(resp, data)
            struct E: Decodable { let embedding: [Float] }
            let decoded = try JSONDecoder().decode(E.self, from: data)
            out.append(decoded.embedding)
        }
        return out
    }

    private func embedBatch(texts: [String], model: String) async throws -> [[Float]] {
        let body: [String: Any] = ["model": model, "input": texts]
        var req = authorizedRequest(baseURL.appendingPathComponent("api/embed"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.validate(resp, data)
        struct E: Decodable { let embeddings: [[Float]] }
        let decoded = try JSONDecoder().decode(E.self, from: data)
        guard decoded.embeddings.count == texts.count else {
            throw InferenceError.decode("ollama /api/embed returned \(decoded.embeddings.count) of \(texts.count)")
        }
        return decoded.embeddings
    }

    static func validate(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw InferenceError.http(http.statusCode, String(data: data.prefix(300), encoding: .utf8) ?? "")
        }
    }
}
