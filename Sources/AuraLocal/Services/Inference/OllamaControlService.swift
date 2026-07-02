import Foundation
import Combine

/// Drives the local Ollama runtime for embedding-model management. The app is
/// non-sandboxed (see `AuraLocal.entitlements`), so this shells out to the `ollama`
/// CLI to install/update/stop models and start/stop the server — the same commands
/// surfaced (copyable) in the UI. All process work runs off the main actor.
@MainActor
final class OllamaControlService: ObservableObject {
    /// Recommended embedding models to offer as one-click pulls (name → blurb).
    static let recommendedEmbeddings: [(model: String, blurb: String)] = [
        ("bge-m3", "1024-dim · 8K context · multilingual (default)"),
        ("qwen3-embedding:0.6b", "1024-dim · 32K context · sub-1GB"),
        ("nomic-embed-text", "768-dim · small & fast"),
    ]

    @Published var binaryPath: String?
    @Published var isBusy = false
    @Published var progress: Double?          // 0…1 during a pull, nil otherwise
    @Published var lastLine: String = ""
    @Published var running: [String] = []     // model names from `ollama ps`

    /// Installed models from `ollama list` — available even when the server is
    /// offline, so the rest of the app (Auto-Configure, Model Zoo, Active Node)
    /// always reflects what's actually on disk.
    @Published private(set) var installed: [ModelInfo] = []
    private var installedFetchedAt: Date?

    /// Fired after any action that can change the catalog or load state
    /// (pull/load/unload/server start/stop) — the app wires this to an immediate
    /// InferenceManager refresh so every view updates at once.
    var onCatalogChanged: (() -> Void)?

    private unowned let settingsStore: SettingsStore

    var isInstalled: Bool { binaryPath != nil }
    private var ollamaBaseURL: URL {
        URL(string: settingsStore.settings.ollamaBaseURL) ?? URL(string: "http://localhost:11434")!
    }

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        binaryPath = Self.resolveBinary()
    }

    // MARK: - Commands

    /// Install or update a model (`ollama pull <model>` re-pulls the latest weights).
    func pull(_ model: String) {
        guard let bin = binaryPath, !isBusy, !model.isEmpty else { return }
        isBusy = true; progress = 0; lastLine = "Pulling \(model)…"
        Task {
            for await line in streamCommand(bin, ["pull", model]) {
                if !line.isEmpty { lastLine = line }
                if let p = Self.parsePercent(line) { progress = p }
            }
            progress = nil
            isBusy = false
            lastLine = "Finished \(model)."
            await refreshRunning()
            await refreshInstalled()
            onCatalogChanged?()
        }
    }

    /// Load a model into memory. Ollama loads on first use, so this warms it with a
    /// tiny embed call — after it returns, the model is resident (shows in `ps`).
    func loadModel(_ model: String) {
        guard isInstalled, !model.isEmpty, !isBusy else { return }
        isBusy = true; lastLine = "Loading \(model) into memory…"
        Task {
            await warm(model)
            isBusy = false
            lastLine = "Loaded \(model)."
            await refreshRunning()
            onCatalogChanged?()
        }
    }

    /// Unload a model from RAM (`ollama stop <model>`).
    func stopModel(_ model: String) {
        guard let bin = binaryPath, !model.isEmpty else { return }
        Task {
            _ = await runCaptured(bin, ["stop", model])
            lastLine = "Stopped \(model)."
            await refreshRunning()
            onCatalogChanged?()
        }
    }

    /// Warm a model into memory via the Ollama embed endpoint (loads + keeps resident).
    private func warm(_ model: String) async {
        var req = URLRequest(url: ollamaBaseURL.appendingPathComponent("api/embed"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "input": "warm"])
        req.timeoutInterval = 180
        _ = try? await URLSession.shared.data(for: req)
    }

    /// Start the Ollama server detached so it outlives this call (`ollama serve`).
    func startServer() {
        guard let bin = binaryPath else { return }
        Task {
            _ = await runCaptured("/bin/sh", ["-c", "\(bin) serve >/dev/null 2>&1 &"])
            lastLine = "Starting Ollama server…"
            // Give the server a beat to bind, then let the app re-discover.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            onCatalogChanged?()
        }
    }

    /// Stop the running Ollama server.
    func stopServer() {
        Task {
            _ = await runCaptured("/usr/bin/pkill", ["-x", "ollama"])
            running = []
            lastLine = "Stopped Ollama server."
            onCatalogChanged?()
        }
    }

    /// The installed-model catalog, refreshed from `ollama list` when stale (>15s).
    /// Used as the discovery fallback while the Ollama server is offline.
    func installedCatalog() async -> [ModelInfo] {
        if let t = installedFetchedAt, Date().timeIntervalSince(t) < 15 { return installed }
        await refreshInstalled()
        return installed
    }

    /// Re-read the installed catalog from Ollama's on-disk model manifests
    /// (`~/.ollama/models/manifests/<registry>/<namespace>/<model>/<tag>`). Unlike
    /// `ollama list`, this needs neither the server nor the CLI, so the app can
    /// report what's installed even while everything is stopped.
    func refreshInstalled() async {
        let runningNow = running
        let models = await Task.detached(priority: .utility) {
            Self.scanManifests(running: runningNow)
        }.value
        installedFetchedAt = Date()
        if installed != models { installed = models }
    }

    nonisolated private static func scanManifests(running: [String]) -> [ModelInfo] {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".ollama/models/manifests")
        func subdirs(_ url: URL) -> [URL] {
            (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey]))?
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true } ?? []
        }
        var out: [ModelInfo] = []
        for registry in subdirs(root) {
            for namespace in subdirs(registry) {
                for modelDir in subdirs(namespace) {
                    let tags = (try? fm.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: nil)) ?? []
                    for tag in tags where !tag.hasDirectoryPath {
                        let base = namespace.lastPathComponent == "library"
                            ? modelDir.lastPathComponent
                            : "\(namespace.lastPathComponent)/\(modelDir.lastPathComponent)"
                        let name = "\(base):\(tag.lastPathComponent)"
                        var size: Int64?
                        if let data = try? Data(contentsOf: tag),
                           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let layers = obj["layers"] as? [[String: Any]] {
                            size = layers.compactMap { ($0["size"] as? NSNumber)?.int64Value }.reduce(0, +)
                        }
                        out.append(ModelInfo(name: name, provider: .ollama, sizeBytes: size,
                                             family: nil, quantization: nil, parameterSize: nil,
                                             type: ModelInfo.looksLikeEmbedding(name) ? .embedding : .chat,
                                             loaded: running.contains { $0.hasPrefix(base) }))
                    }
                }
            }
        }
        return out.sorted { $0.name < $1.name }
    }

    /// Refresh the list of models currently resident in memory (`ollama ps`).
    func refreshRunning() async {
        guard let bin = binaryPath else { running = []; return }
        let out = await runCaptured(bin, ["ps"])
        var names: [String] = []
        for (i, line) in out.split(separator: "\n").enumerated() where i > 0 {  // skip header
            if let first = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).first {
                names.append(String(first))
            }
        }
        running = names
    }

    // MARK: - Process helpers (off-main)

    /// Run a command to completion off-main and return its combined stdout/stderr.
    private func runCaptured(_ bin: String, _ args: [String]) async -> String {
        await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: bin)
            proc.arguments = args
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            do { try proc.run() } catch { return "" }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        }.value
    }

    /// Stream a long-running command's output line-by-line (used for `pull` progress).
    private nonisolated func streamCommand(_ bin: String, _ args: [String]) -> AsyncStream<String> {
        AsyncStream { continuation in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: bin)
            proc.arguments = args
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return }
                for chunk in s.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
                    continuation.yield(String(chunk))
                }
            }
            proc.terminationHandler = { _ in
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.finish()
            }
            do { try proc.run() } catch { continuation.finish() }
            continuation.onTermination = { _ in if proc.isRunning { proc.terminate() } }
        }
    }

    // MARK: - Binary resolution + parsing

    private static func resolveBinary() -> String? {
        let candidates = ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama", "/usr/bin/ollama"]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }
        // Fall back to `which ollama` (covers custom install locations on PATH).
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["ollama"]
        let pipe = Pipe(); proc.standardOutput = pipe
        guard (try? proc.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    /// Best-effort extraction of a "NN%" progress token from a CLI line.
    static func parsePercent(_ s: String) -> Double? {
        guard let r = s.range(of: #"(\d{1,3})%"#, options: .regularExpression) else { return nil }
        guard let v = Double(s[r].dropLast()) else { return nil }
        return min(1, max(0, v / 100))
    }
}
