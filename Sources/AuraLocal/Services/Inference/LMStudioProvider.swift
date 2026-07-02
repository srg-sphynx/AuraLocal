import Foundation

/// Connector for LM Studio's OpenAI-compatible server (default http://localhost:1234).
/// Streams via true Server-Sent Events (`data: {…}` frames, terminated by `[DONE]`).
struct LMStudioProvider: InferenceProvider {
    let kind: ProviderKind = .lmstudio
    let baseURL: URL
    let apiKey: String

    private var v1: URL { baseURL.appendingPathComponent("v1") }
    private var apiV0: URL { baseURL.appendingPathComponent("api/v0") }

    func ping() async -> Bool {
        var req = authorizedRequest(v1.appendingPathComponent("models"))
        req.timeoutInterval = 2
        return (try? await URLSession.shared.data(for: req)) != nil
    }

    func listModels() async throws -> [ModelInfo] {
        // Prefer the native REST API (v0): it reports `type` (llm/embeddings/vlm)
        // and `state` (loaded/not-loaded) — the signal we need to know whether the
        // embedding model is actually resident, not merely downloaded.
        if let detailed = try? await listModelsV0(), !detailed.isEmpty { return detailed }

        // Fallback for older LM Studio builds without /api/v0.
        let (data, resp) = try await URLSession.shared.data(for: authorizedRequest(v1.appendingPathComponent("models")))
        try OllamaProvider.validate(resp, data)
        struct ModelsResp: Decodable { struct M: Decodable { let id: String }; let data: [M] }
        let decoded = try JSONDecoder().decode(ModelsResp.self, from: data)
        return decoded.data.map {
            ModelInfo(name: $0.id, provider: .lmstudio,
                      type: ModelInfo.looksLikeEmbedding($0.id) ? .embedding : .chat)
        }
    }

    private func listModelsV0() async throws -> [ModelInfo] {
        var req = authorizedRequest(apiV0.appendingPathComponent("models"))
        req.timeoutInterval = 4
        let (data, resp) = try await URLSession.shared.data(for: req)
        try OllamaProvider.validate(resp, data)
        struct V0: Decodable {
            struct M: Decodable {
                let id: String
                let type: String?
                let state: String?
                let quantization: String?
                let arch: String?
                let max_context_length: Int?
            }
            let data: [M]
        }
        let decoded = try JSONDecoder().decode(V0.self, from: data)
        return decoded.data.map { m in
            let type: ModelType
            switch (m.type ?? "").lowercased() {
            case "embeddings", "embedding": type = .embedding
            case "vlm": type = .vision
            case "llm": type = .chat
            default: type = ModelInfo.looksLikeEmbedding(m.id) ? .embedding : .chat
            }
            return ModelInfo(name: m.id, provider: .lmstudio,
                             family: m.arch, quantization: m.quantization,
                             type: type, loaded: (m.state ?? "").lowercased() == "loaded",
                             maxContextLength: m.max_context_length)
        }
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
                        "temperature": config.temperature,
                        "top_p": config.topP,
                        "max_tokens": config.maxTokens
                    ]
                    var req = authorizedRequest(v1.appendingPathComponent("chat/completions"))
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw InferenceError.http(http.statusCode, "lmstudio chat failed")
                    }

                    var emitted = 0
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" {
                            continuation.yield(StreamToken(text: "", done: true, evalCount: emitted))
                            break
                        }
                        guard let data = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = obj["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any]
                        else { continue }
                        let content = delta["content"] as? String ?? ""
                        if !content.isEmpty { emitted += 1 }
                        let finish = choices.first?["finish_reason"] as? String
                        continuation.yield(StreamToken(text: content, done: finish != nil, evalCount: emitted))
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
        let body: [String: Any] = ["model": model, "input": texts]
        var req = authorizedRequest(v1.appendingPathComponent("embeddings"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try OllamaProvider.validate(resp, data)
        struct E: Decodable { struct D: Decodable { let embedding: [Float] }; let data: [D] }
        let decoded = try JSONDecoder().decode(E.self, from: data)
        return decoded.data.map { $0.embedding }
    }
}
