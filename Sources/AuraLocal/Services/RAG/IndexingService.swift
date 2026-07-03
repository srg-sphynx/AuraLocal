import Foundation
import Combine

/// Orchestrates the local RAG pipeline. The vault is scanned **once** into a
/// persistent keyword (FTS) index — cheap, no model calls — and the per-file
/// `files` table records a content hash so re-scans skip unchanged files and a
/// restart never re-embeds. Vectors are produced eagerly (Full mode) or lazily on
/// the small set of candidates each query needs (Smart mode).
@MainActor
final class IndexingService: ObservableObject {

    // Live state surfaced by the Indexing ("Vectorization Engine") view.
    @Published var isIndexing = false
    @Published var activeProjectID: UUID?
    @Published var progress: Double = 0
    @Published var currentFileName: String = ""
    @Published var processedCount = 0
    @Published var totalCount = 0
    @Published var throughputMBs: Double = 0
    @Published var statusMessage = "Idle"
    @Published var lastError: String?
    @Published var embeddingIntensity: [Double] = Array(repeating: 0, count: 40)
    /// A short note about the last retrieval (e.g. "keyword search — embed model not loaded").
    @Published var retrievalNote: String?

    // Per-project indexed-file inventory (drives the Inspector + Knowledge Base).
    @Published var indexedFiles: [UUID: [IndexedFile]] = [:]

    private let database: AppDatabase
    private unowned let settingsStore: SettingsStore
    private unowned let inference: InferenceManager
    private var indexTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// Per-project ANN indexes, lazily loaded from their sidecar files.
    private var vectorIndexes: [UUID: VectorIndex] = [:]
    /// Below this many embedded chunks the exact cosine scan is fast enough — skip ANN.
    private static let annMinChunks = 2000
    /// Cap (seconds) on a single query embed before retrieval degrades to keyword
    /// search. Guards the first query against a freshly-indexed vault, when the embed
    /// server may be cold or still saturated by the bulk embedding pass — without this
    /// a stalled request would leave the whole answer hanging with no visible output.
    private static let queryEmbedTimeout: Double = 20

    func annIndex(for projectID: UUID) -> VectorIndex {
        if let idx = vectorIndexes[projectID] { return idx }
        let idx = VectorIndex(projectID: projectID)
        vectorIndexes[projectID] = idx
        return idx
    }

    /// Drop all ANN sidecar files (used by clear-index / reset).
    func clearVectorIndexes() {
        for idx in vectorIndexes.values { idx.delete() }
        vectorIndexes.removeAll()
    }

    init(database: AppDatabase, settingsStore: SettingsStore, inference: InferenceManager) {
        self.database = database
        self.settingsStore = settingsStore
        self.inference = inference

        // Auto-resume: when the embedding model becomes ready (e.g. the user loads it
        // after adding a vault, or launches with the server offline then starts it),
        // embed any chunks still lacking a vector — no manual re-index needed.
        inference.$embeddingStatus
            .map(\.isReady)
            .removeDuplicates()
            .sink { [weak self] ready in
                guard ready else { return }
                Task { @MainActor in self?.resumeEmbeddingForAll() }
            }
            .store(in: &cancellables)
    }

    private var settings: AppSettings { settingsStore.settings }

    func cancel() {
        indexTask?.cancel()
        isIndexing = false
        statusMessage = "Cancelled"
    }

    // MARK: - Inventory (rebuilt from disk; no embedding)

    /// Populate the in-memory inventory from the persisted `files` table so the UI
    /// shows the indexed state instantly on launch — without re-scanning or embedding.
    func rebuildInventory(projects: [Project]) {
        for p in projects { refreshInventory(p.id) }
    }

    /// Async inventory load — reads each project's file states off the main actor so a
    /// large vault (32k+ files) never stalls launch. Publishes results as they arrive.
    func rebuildInventoryAsync(projects: [Project]) {
        let db = database
        let ids = projects.map(\.id)
        Task {
            for id in ids {
                let states = await Task.detached(priority: .utility) { db.loadFileStates(projectID: id) }.value
                self.indexedFiles[id] = states.map(Self.indexedFile(from:))
            }
        }
    }

    func refreshInventory(_ projectID: UUID) {
        let states = database.loadFileStates(projectID: projectID)
        indexedFiles[projectID] = states.map(Self.indexedFile(from:))
    }

    private static func indexedFile(from f: FileState) -> IndexedFile {
        IndexedFile(projectID: f.projectID, relativePath: f.relPath, fileName: f.fileName,
                    ext: f.ext, byteSize: f.byteSize,
                    modifiedAt: Date(timeIntervalSince1970: f.mtime),
                    chunkCount: f.chunkCount, embeddedChunkCount: f.embeddedChunkCount,
                    tokenEstimate: f.tokenEstimate,
                    status: IndexStatus(rawValue: f.status) ?? .synced,
                    tags: f.tags, aliases: f.aliases,
                    lastIndexedAt: f.lastIndexedAt > 0 ? Date(timeIntervalSince1970: f.lastIndexedAt) : nil,
                    embedModel: f.embedModel,
                    errorMessage: f.errorMessage, title: f.title)
    }

    // MARK: - Index a project

    func index(project: Project, force: Bool = false) {
        indexTask?.cancel()
        indexTask = Task { await self.runIndex(project: project, force: force) }
    }

    private func runIndex(project: Project, force: Bool) async {
        isIndexing = true
        activeProjectID = project.id
        lastError = nil
        progress = 0
        processedCount = 0
        statusMessage = "Scanning vault…"
        defer { isIndexing = false }

        let snapshot = settings
        let outcome = await scanAndLexicalIndex(project: project, settings: snapshot, force: force)

        if Task.isCancelled { statusMessage = "Cancelled"; return }
        if let err = outcome.error {
            lastError = err; statusMessage = "Error"
            Log.indexing.error(err)
            ToastCenter.shared.post(err, level: .error)
            return
        }

        refreshInventory(project.id)

        // Always embed everything that still lacks a vector for the current model
        // (Full Embed is the only mode in v2 — queries then only embed the query).
        await runEmbeddingPass(projectID: project.id)
        await maybeBuildANN(projectID: project.id)

        progress = 1
        let chunks = database.chunkCount(projectID: project.id)
        let embedded = database.embeddedChunkCount(projectID: project.id)
        statusMessage = "Synced • \(embedded)/\(chunks) chunks embedded"
    }

    private struct ScanOutcome { var total = 0; var changed = 0; var deleted = 0; var error: String? }

    /// Off-main scan + lexical indexing. Holds one sustained security-scoped access
    /// for the whole walk (essential at 32k files) and posts throttled progress.
    nonisolated private func scanAndLexicalIndex(project: Project, settings: AppSettings, force: Bool) async -> ScanOutcome {
        guard let root = try? BookmarkStore.resolve(project.bookmark).url else {
            return ScanOutcome(error: "Could not access vault (bookmark unresolved).")
        }
        let didAccess = root.startAccessingSecurityScopedResource()
        defer { if didAccess { root.stopAccessingSecurityScopedResource() } }

        let scanned = FileIngestor.scan(root: root, settings: settings)
        let prior = Dictionary(database.loadFileStates(projectID: project.id).map { ($0.relPath, $0) },
                               uniquingKeysWith: { a, _ in a })
        let chunkHash = settings.chunkParamsHash

        await MainActor.run { self.totalCount = scanned.count; self.statusMessage = "Indexing \(scanned.count) files…" }

        var seen = Set<String>()
        var changed = 0
        var lastTick = Date()

        for (i, file) in scanned.enumerated() {
            if Task.isCancelled { break }
            seen.insert(file.relativePath)

            let quickHash = "\(file.byteSize):\(Int(file.modifiedAt.timeIntervalSince1970))"
            let unchanged = !force
                && prior[file.relativePath].map { $0.contentHash == quickHash && $0.chunkParamsHash == chunkHash } == true

            if !unchanged {
                autoreleasepool {
                    indexOneFile(project: project, file: file, quickHash: quickHash, chunkHash: chunkHash, settings: settings)
                }
                changed += 1
            }

            if i % 32 == 0 || Date().timeIntervalSince(lastTick) > 0.15 {
                lastTick = Date()
                let done = i + 1, name = file.fileName, didChange = changed
                await MainActor.run {
                    self.processedCount = done
                    self.progress = Double(done) / Double(max(1, scanned.count))
                    self.currentFileName = name
                    if didChange > 0 { self.bumpIntensity(1) }
                }
            }
        }

        let deleted = database.deleteMissingFiles(projectID: project.id, keep: seen)
        return ScanOutcome(total: scanned.count, changed: changed, deleted: deleted.count)
    }

    /// Parse + chunk + persist a single file as text-only chunks (+ FTS rows). Every
    /// supported format is normalized to Markdown by `DocumentExtractor` so the one
    /// heading-aware chunker handles them uniformly. Failures are recorded (never
    /// crash the walk) with a reason surfaced to the Issues list.
    nonisolated private func indexOneFile(project: Project, file: ScannedFile,
                                          quickHash: String, chunkHash: String, settings: AppSettings) {
        // Large-file guardrail — skip and record rather than block the UI on a huge file.
        let maxBytes = Int64(max(1, settings.maxFileSizeMB)) * 1_048_576
        if file.byteSize > maxBytes {
            let mb = Int(file.byteSize / 1_048_576)
            let msg = AuraError.fileTooLarge(path: file.relativePath, mb: mb, limit: settings.maxFileSizeMB).errorDescription
            Log.ingest.warning(msg ?? "File too large: \(file.relativePath)")
            recordFile(project: project, file: file, quickHash: quickHash, chunkHash: chunkHash,
                       chunkCount: 0, tokenEstimate: 0, tags: [], aliases: [],
                       status: .excluded, error: msg, title: nil)
            return
        }

        guard let doc = DocumentExtractor.extract(file, settings: settings) else {
            let msg = AuraError.fileUnreadable(path: file.relativePath).errorDescription
            Log.ingest.warning("Unreadable file: \(file.relativePath)")
            recordFile(project: project, file: file, quickHash: quickHash, chunkHash: chunkHash,
                       chunkCount: 0, tokenEstimate: 0, tags: [], aliases: [],
                       status: .error, error: msg, title: nil)
            return
        }

        let params = chunkParam(chunkHash)
        let chunks = MarkdownChunker.chunk(doc.markdown, maxTokens: params.max, overlap: params.overlap,
                                           docContext: Self.contextLine(title: doc.title, tags: doc.tags))
        let rows = chunks.map {
            ChunkRow(heading: $0.heading, ordinal: $0.ordinal, text: $0.text,
                     tags: doc.tags, tokenEstimate: $0.tokenEstimate, embedding: [], textHash: "")
        }
        try? database.replaceChunks(projectID: project.id, filePath: file.relativePath,
                                    fileName: file.fileName, rows: rows)

        let warning = doc.warnings.isEmpty ? nil : doc.warnings.joined(separator: " ")
        let status: IndexStatus = chunks.isEmpty ? .error : .synced
        let error = chunks.isEmpty ? (warning ?? "No indexable text extracted.") : warning
        if let warning { Log.ingest.info("\(file.relativePath): \(warning)") }
        recordFile(project: project, file: file, quickHash: quickHash, chunkHash: chunkHash,
                   chunkCount: chunks.count, tokenEstimate: chunks.reduce(0) { $0 + $1.tokenEstimate },
                   tags: doc.tags, aliases: doc.aliases, status: status, error: error, title: doc.title)
    }

    /// Compact, model-free per-chunk context line (title + top tags).
    nonisolated private static func contextLine(title: String?, tags: [String]) -> String? {
        var parts: [String] = []
        if let t = title?.trimmingCharacters(in: .whitespaces), !t.isEmpty { parts.append(t) }
        if !tags.isEmpty { parts.append("tags: " + tags.prefix(6).joined(separator: ", ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Upsert a `files` row with the given outcome (shared by success + failure paths).
    nonisolated private func recordFile(project: Project, file: ScannedFile, quickHash: String, chunkHash: String,
                                        chunkCount: Int, tokenEstimate: Int, tags: [String], aliases: [String],
                                        status: IndexStatus, error: String?, title: String?) {
        database.upsertFileState(FileState(projectID: project.id, relPath: file.relativePath,
            fileName: file.fileName, ext: file.ext, byteSize: file.byteSize,
            mtime: file.modifiedAt.timeIntervalSince1970, contentHash: quickHash,
            chunkParamsHash: chunkHash, embedModel: "", embedDim: 0, chunkCount: chunkCount,
            embeddedChunkCount: 0, tokenEstimate: tokenEstimate, status: status.rawValue,
            tags: tags, aliases: aliases, lastIndexedAt: Date().timeIntervalSince1970,
            errorMessage: error, title: title))
    }

    /// Decode the "max:overlap" chunk-params hash back to its components.
    nonisolated private func chunkParam(_ hash: String) -> (max: Int, overlap: Int) {
        let parts = hash.split(separator: ":").compactMap { Int($0) }
        return (parts.first ?? 512, parts.count > 1 ? parts[1] : 64)
    }

    // MARK: - Full-mode embedding pass

    private func runEmbeddingPass(projectID: UUID) async {
        guard inference.embeddingReady, !settings.embeddingModel.isEmpty else {
            statusMessage = "Keyword index built — load an embedding model to vectorize."
            return
        }
        let model = settings.embeddingModel
        let provider = ProviderFactory.make(settings.embeddingProvider, settings: settings)
        let total = database.countNeedingEmbedding(projectID: projectID, model: model)
        guard total > 0 else { refreshInventory(projectID); return }

        var done = 0
        statusMessage = "Embedding \(total) chunks…"
        let stride = max(64, settings.embeddingBatchSize * 4)

        while !Task.isCancelled {
            let batch = database.chunksNeedingEmbedding(projectID: projectID, model: model, limit: stride)
            if batch.isEmpty { break }
            if let vecs = await embedBatched(batch.map { $0.text }, model: model, provider: provider,
                                             batchSize: settings.embeddingBatchSize,
                                             concurrency: settings.embeddingConcurrency) {
                let updates = zip(batch, vecs).map { (id: $0.0.id, vector: $0.1, model: model) }
                try? database.updateChunkVectors(updates)
                done += batch.count
                progress = total > 0 ? min(1, Double(done) / Double(total)) : 1
                statusMessage = "Embedded \(done)/\(total) chunks…"
                bumpIntensity(1)
            } else {
                lastError = "Embedding failed (\(model)); text kept for keyword search."
                Log.indexing.error(lastError!)
                ToastCenter.shared.post(lastError!, level: .warning)
                break
            }
        }
        refreshInventory(projectID)
    }

    // MARK: - Auto-resume embedding (model became ready)

    /// Kicked when the embedding model transitions to ready. Embeds any chunks still
    /// lacking a vector across all known projects. No-op if an index is already running.
    func resumeEmbeddingForAll() {
        guard !isIndexing, inference.embeddingReady, !settings.embeddingModel.isEmpty else { return }
        let ids = Array(indexedFiles.keys)
        guard !ids.isEmpty else { return }
        indexTask?.cancel()
        indexTask = Task { await self.runResumePass(projectIDs: ids) }
    }

    private func runResumePass(projectIDs: [UUID]) async {
        let model = settings.embeddingModel
        let pending = projectIDs.filter { database.countNeedingEmbedding(projectID: $0, model: model) > 0 }
        guard !pending.isEmpty else { return }

        isIndexing = true
        lastError = nil
        defer { isIndexing = false }
        for id in pending {
            if Task.isCancelled { break }
            activeProjectID = id
            await runEmbeddingPass(projectID: id)
            await maybeBuildANN(projectID: id)
        }
        progress = 1
        statusMessage = "Embedding up to date."
    }

    // MARK: - ANN index build

    /// Build (or rebuild) the project's ANN index when it's stale and the vault is big
    /// enough to benefit. Centroids are computed off-main and installed on the main
    /// actor; the heavy bucket-assignment pass streams vectors off-main. All best-effort:
    /// if anything fails, retrieval simply falls back to the exact cosine scan.
    private func maybeBuildANN(projectID: UUID) async {
        guard settings.annEnabled, !Task.isCancelled else { return }
        let count = database.embeddedChunkCount(projectID: projectID)
        let index = annIndex(for: projectID)
        guard index.needsRebuild(currentChunks: count, minChunks: Self.annMinChunks) else { return }

        statusMessage = "Building fast search index…"
        Log.indexing.info("Building ANN index for project over \(count) chunks")
        let nlist = min(512, max(16, Int(Double(count).squareRoot())))
        let db = database
        let sampleLimit = min(count, 12000)

        let sample = await Task.detached(priority: .utility) { db.sampleVectors(projectID: projectID, limit: sampleLimit) }.value
        let centroids = await Task.detached(priority: .utility) { VectorIndex.computeCentroids(sample: sample, nlist: nlist) }.value
        guard !centroids.isEmpty, !Task.isCancelled else {
            statusMessage = "Fast index skipped (too few vectors)."
            return
        }
        index.install(centroids: centroids, totalChunks: count)
        let snapshot = centroids
        let assigned = await Task.detached(priority: .utility) {
            db.assignBuckets(projectID: projectID) { VectorIndex.nearestCentroid($0, snapshot) }
        }.value
        Log.indexing.info("ANN index ready: \(centroids.count) buckets, \(assigned) chunks assigned")
    }

    // MARK: - Single-file re-index (vault watcher)

    func reindexFile(project: Project, relativePath: String) {
        Task { await self.runReindexFile(project: project, relativePath: relativePath) }
    }

    nonisolated private func runReindexFile(project: Project, relativePath: String) async {
        let snap = await MainActor.run { self.settings }
        guard let root = try? BookmarkStore.resolve(project.bookmark).url else { return }
        let didAccess = root.startAccessingSecurityScopedResource()
        defer { if didAccess { root.stopAccessingSecurityScopedResource() } }

        let url = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            try? database.deleteFile(projectID: project.id, filePath: relativePath)
            await MainActor.run {
                self.indexedFiles[project.id]?.removeAll { $0.relativePath == relativePath }
                self.statusMessage = "Removed \(relativePath)"
            }
            return
        }
        let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let file = ScannedFile(url: url, relativePath: relativePath, fileName: url.lastPathComponent,
                               ext: url.pathExtension.lowercased(), byteSize: Int64(v?.fileSize ?? 0),
                               modifiedAt: v?.contentModificationDate ?? Date())
        let quick = "\(file.byteSize):\(Int(file.modifiedAt.timeIntervalSince1970))"
        indexOneFile(project: project, file: file, quickHash: quick, chunkHash: snap.chunkParamsHash, settings: snap)
        await MainActor.run {
            self.refreshInventory(project.id)
            self.statusMessage = "Auto-refreshed \(file.fileName)"
        }
        await self.runEmbeddingPass(projectID: project.id)
    }

    // MARK: - Retrieval (Smart Scan + hybrid re-rank)

    func retrieve(query: String, project: Project) async -> [RetrievedChunk] {
        retrievalNote = nil
        let window = max(1, settings.candidateFileWindow)

        // 1. Keyword candidates (BM25) — chunks from the top-N files by keyword score.
        let rawCandidates = database.ftsCandidates(projectID: project.id, query: query, limit: window * 12)
        let topFiles = orderedTopFiles(rawCandidates, limit: window)
        let keywordIDs = rawCandidates.filter { topFiles.contains($0.filePath) }.map { $0.chunkID }
        let bm = Dictionary(rawCandidates.map { ($0.chunkID, $0.bm25) }, uniquingKeysWith: { a, _ in a })

        // 2. Semantic path — embed ONLY the query (chunks are already vectorized), then
        //    union the keyword candidates with a pure-cosine top-K over the whole store.
        //    This is what lets a reworded follow-up surface chunks it shares no keywords
        //    with, and it no longer re-embeds anything at query time.
        if inference.embeddingReady, !settings.embeddingModel.isEmpty {
            let provider = ProviderFactory.make(settings.embeddingProvider, settings: settings)
            let qv = await Self.embedQuery(provider: provider, query: query,
                                           model: settings.embeddingModel, timeout: Self.queryEmbedTimeout)
            if let qv, !qv.isEmpty {
                // ANN plan (computed on-main from the in-memory centroids). Empty/nil ⇒
                // exact scan. This is where the 888k-chunk O(N) jitter gets cut.
                let annBuckets = annBucketPlan(project: project.id, queryVector: qv)
                let semantic = await semanticScan(projectID: project.id, queryVector: qv,
                                                  k: max(1, settings.semanticCandidateCount),
                                                  buckets: annBuckets)
                var ids = Set(keywordIDs)
                for s in semantic { ids.insert(s.chunkID) }
                let chunks = database.chunksByIDs(Array(ids))
                let scored: [(chunk: EmbeddedChunk, cos: Double, bm: Double)] = chunks.compactMap { c in
                    guard c.vector.count == qv.count else { return nil }
                    return (c, Double(VectorMath.cosine(qv, c.vector)), bm[c.id] ?? 0)
                }
                if !scored.isEmpty { return await postProcess(rankCandidates(scored), query: query, project: project) }
                retrievalNote = "No embedded chunks yet — finish indexing to enable semantic search."
            } else {
                retrievalNote = "Semantic step unavailable — showing keyword matches."
            }
        } else {
            retrievalNote = inference.embeddingStatus.message(model: settings.embeddingModel,
                                                              provider: settings.embeddingProvider)
        }

        // 3. Lexical fallback (no embed model, or query embed failed).
        guard !keywordIDs.isEmpty else {
            if retrievalNote == nil { retrievalNote = "No keyword matches in this vault." }
            return []
        }
        return await postProcess(lexicalRank(database.chunksByIDs(keywordIDs), bm: bm), query: query, project: project)
    }

    /// Nearest ANN buckets for the query, or nil when ANN is disabled/unbuilt (⇒ exact scan).
    private func annBucketPlan(project: UUID, queryVector: [Float]) -> Set<Int>? {
        guard settings.annEnabled else { return nil }
        let idx = annIndex(for: project)
        guard idx.isBuilt else { return nil }
        let nprobe = max(8, idx.centroids.count / 8)
        let buckets = idx.nearestBuckets(queryVector, nprobe: nprobe)
        return buckets.isEmpty ? nil : buckets
    }

    /// Off-main semantic recall. Uses the ANN bucket scan when `buckets` is provided,
    /// else the exact full scan. Detached so the cosine work never blocks the UI.
    nonisolated private func semanticScan(projectID: UUID, queryVector: [Float], k: Int,
                                          buckets: Set<Int>?) async -> [(chunkID: Int64, cos: Double)] {
        let db = database
        return await Task.detached(priority: .userInitiated) {
            if let buckets, !buckets.isEmpty {
                return db.semanticTopKInBuckets(projectID: projectID, queryVector: queryVector, buckets: buckets, k: k)
            }
            return db.semanticTopK(projectID: projectID, queryVector: queryVector, k: k)
        }.value
    }

    /// Embed a single query with a hard timeout. Returns nil if the embed fails or
    /// doesn't return in `timeout` seconds, so retrieval falls back to keyword search
    /// instead of stalling on a cold/busy embed server.
    nonisolated private static func embedQuery(provider: InferenceProvider, query: String,
                                               model: String, timeout: Double) async -> [Float]? {
        await withTaskGroup(of: [Float]?.self) { group in
            group.addTask { (try? await provider.embed(texts: [query], model: model))?.first }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let result: [Float]? = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    // MARK: - Post-processing (optional LLM re-rank + parent-document expansion)

    private func postProcess(_ ranked: [RetrievedChunk], query: String, project: Project) async -> [RetrievedChunk] {
        var result = ranked
        if settings.rerankMode == .llmJudge, result.count > 1 {
            result = await llmRerank(result, query: query)
        }
        if settings.parentExpansion {
            result = expandParents(result, project: project)
        }
        return result
    }

    /// Small-to-big: replace each chunk's text with its neighbors (same file, adjacent
    /// ordinals) merged in order, giving the LLM more coherent context per citation.
    private func expandParents(_ chunks: [RetrievedChunk], project: Project, radius: Int = 1) -> [RetrievedChunk] {
        chunks.map { c in
            let neighbors = database.neighborChunks(projectID: project.id, filePath: c.filePath,
                                                    ordinal: c.ordinal, radius: radius)
            guard neighbors.count > 1 else { return c }
            var out = c
            out.text = neighbors.sorted { $0.ordinal < $1.ordinal }.map(\.text).joined(separator: "\n\n")
            return out
        }
    }

    /// Ask the local chat model to pick the most relevant chunks (best-effort — on any
    /// failure the original RRF order is kept). Only the top slice is re-ranked to bound cost.
    private func llmRerank(_ chunks: [RetrievedChunk], query: String, window: Int = 8) async -> [RetrievedChunk] {
        let head = Array(chunks.prefix(window))
        let tail = Array(chunks.dropFirst(window))
        let listing = head.enumerated().map { i, c in
            "[\(i + 1)] \(c.fileName)\(c.heading.map { " — \($0)" } ?? ""): \(c.text.prefix(240))"
        }.joined(separator: "\n")
        let prompt = """
        Rank the passages by how well they help answer the question. Reply with ONLY a comma-separated list of passage numbers, best first.

        Question: \(query)

        Passages:
        \(listing)
        """
        guard let reply = await inference.complete(prompt: prompt,
                                                   system: "You are a precise retrieval re-ranker.",
                                                   maxTokens: 60) else { return chunks }
        let order = reply.split { !$0.isNumber }.compactMap { Int($0) }.filter { $0 >= 1 && $0 <= head.count }
        guard !order.isEmpty else { return chunks }
        var seen = Set<Int>(); var reordered: [RetrievedChunk] = []
        for n in order where !seen.contains(n) { seen.insert(n); reordered.append(head[n - 1]) }
        for (i, c) in head.enumerated() where !seen.contains(i + 1) { reordered.append(c) }
        return reordered + tail
    }

    private func orderedTopFiles(_ cands: [FTSCandidate], limit: Int) -> Set<String> {
        var seen = Set<String>(); var ordered: [String] = []
        for c in cands where !seen.contains(c.filePath) {
            seen.insert(c.filePath); ordered.append(c.filePath)
            if ordered.count >= limit { break }
        }
        return Set(ordered)
    }

    /// Filter by cosine threshold, then order per `rerankMode`:
    ///  - `.off`: pure semantic (cosine) order.
    ///  - `.hybridRRF` / `.llmJudge`: Reciprocal Rank Fusion of the semantic rank and
    ///    the BM25 keyword rank — parameter-free and more robust than a weighted blend.
    ///    (`.llmJudge` then re-orders the top slice in `postProcess`.)
    private func rankCandidates(_ scored: [(chunk: EmbeddedChunk, cos: Double, bm: Double)]) -> [RetrievedChunk] {
        let kept = scored.filter { $0.cos >= settings.minSimilarity }
        guard !kept.isEmpty else { retrievalNote = "No chunks above the similarity threshold."; return [] }

        if settings.rerankMode == .off {
            return kept.sorted { $0.cos > $1.cos }
                .prefix(settings.retrievalTopK)
                .map { toRetrieved($0.chunk, score: ($0.cos + 1) / 2) }
        }

        // Reciprocal Rank Fusion. Rank 0 = best in each list. Only candidates that
        // actually matched keywords get a keyword rank; others contribute semantic only.
        let k0 = 60.0
        let semanticOrder = kept.enumerated().sorted { $0.element.cos > $1.element.cos }
        var semRank = [Int: Int]()   // candidate index → rank
        for (r, e) in semanticOrder.enumerated() { semRank[e.offset] = r }

        let keywordOrder = kept.enumerated()
            .filter { $0.element.bm != 0 }
            .sorted { $0.element.bm < $1.element.bm }   // lower bm25 = better
        var kwRank = [Int: Int]()
        for (r, e) in keywordOrder.enumerated() { kwRank[e.offset] = r }

        let fused = kept.enumerated().map { (i, it) -> (EmbeddedChunk, Double) in
            var score = 1.0 / (k0 + Double(semRank[i] ?? kept.count))
            if let kr = kwRank[i] { score += 1.0 / (k0 + Double(kr)) }
            return (it.chunk, score)
        }.sorted { $0.1 > $1.1 }

        return fused.prefix(settings.retrievalTopK).map { toRetrieved($0.0, score: $0.1) }
    }

    private func lexicalRank(_ chunks: [EmbeddedChunk], bm: [Int64: Double]) -> [RetrievedChunk] {
        let sorted = chunks.sorted { (bm[$0.id] ?? 0) < (bm[$1.id] ?? 0) }
        let n = max(1, sorted.count)
        return sorted.prefix(settings.retrievalTopK).enumerated().map { i, c in
            toRetrieved(c, score: 1 - Double(i) / Double(n))
        }
    }

    private func toRetrieved(_ c: EmbeddedChunk, score: Double) -> RetrievedChunk {
        RetrievedChunk(chunkID: c.id, fileName: c.fileName, filePath: c.filePath,
                       heading: c.heading, text: c.text, score: score, tags: c.tags, ordinal: c.ordinal)
    }

    // MARK: - Batched embedding with retry/backoff

    /// Embed `texts` preserving order, in bounded-concurrency batches. Returns nil
    /// if any batch ultimately fails (caller falls back to keyword search).
    nonisolated private func embedBatched(_ texts: [String], model: String, provider: InferenceProvider,
                                          batchSize: Int, concurrency: Int) async -> [[Float]]? {
        guard !texts.isEmpty else { return [] }
        let size = max(1, batchSize)
        var batches: [[String]] = []
        var i = 0
        while i < texts.count { batches.append(Array(texts[i..<min(i + size, texts.count)])); i += size }

        var results = [[[Float]]?](repeating: nil, count: batches.count)
        let lanes = max(1, min(concurrency, batches.count))

        await withTaskGroup(of: (Int, [[Float]]?).self) { group in
            var next = 0
            func submit(_ idx: Int) {
                let batch = batches[idx]
                group.addTask { (idx, await Self.embedOneBatch(batch, model: model, provider: provider)) }
            }
            while next < lanes { submit(next); next += 1 }
            while let (idx, vecs) = await group.next() {
                results[idx] = vecs
                if next < batches.count { submit(next); next += 1 }
            }
        }

        var out: [[Float]] = []
        for r in results { guard let r else { return nil }; out += r }
        return out.count == texts.count ? out : nil
    }

    nonisolated private static func embedOneBatch(_ batch: [String], model: String, provider: InferenceProvider) async -> [[Float]]? {
        var delay: UInt64 = 250_000_000
        for attempt in 0..<3 {
            if Task.isCancelled { return nil }
            if let v = try? await provider.embed(texts: batch, model: model), v.count == batch.count, v.allSatisfy({ !$0.isEmpty }) {
                return v
            }
            if attempt < 2 { try? await Task.sleep(nanoseconds: delay); delay *= 2 }
        }
        return nil
    }

    // MARK: - Misc

    private func bumpIntensity(_ v: Double) {
        embeddingIntensity.removeFirst()
        embeddingIntensity.append(min(1, 0.4 + 0.6 * v))
    }

    func totalChunks() -> Int { database.totalChunkCount() }
    func chunkCount(for projectID: UUID) -> Int { database.chunkCount(projectID: projectID) }
    func embeddedCount(for projectID: UUID) -> Int { database.embeddedChunkCount(projectID: projectID) }
}
