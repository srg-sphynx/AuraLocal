import Foundation

/// Self-contained on-disk **ANN index** for one project's vector store.
///
/// Design: a coarse-quantization (IVF) index rather than an in-memory HNSW graph.
/// At 888k × 1024-dim, holding the full graph + vectors in RAM would cost ~2 GB;
/// IVF instead keeps only a small set of **centroids** in memory (built with
/// spherical k-means) and stores each chunk's nearest-centroid `bucket` in SQLite.
/// A query finds its nearest `nprobe` centroids and the DB scans only those buckets
/// (plus the always-probed `-1` unassigned bucket). This is memory-bounded, cheap to
/// update incrementally, and — crucially — degrades gracefully: if the index is
/// missing or stale the caller falls back to the exact `semanticTopK` scan.
///
/// Vectors are L2-normalized before k-means so nearest-by-dot == nearest-by-cosine,
/// matching the retrieval metric.
final class VectorIndex {
    let projectID: UUID
    private(set) var centroids: [[Float]] = []   // normalized
    /// Chunk count at last build — used to decide when a rebuild is worthwhile.
    private(set) var builtChunkCount: Int = 0

    var isBuilt: Bool { !centroids.isEmpty }

    init(projectID: UUID) {
        self.projectID = projectID
        load()
    }

    // MARK: - Query

    /// Indices of the `nprobe` centroids nearest to `query` (by cosine).
    func nearestBuckets(_ query: [Float], nprobe: Int) -> Set<Int> {
        guard isBuilt, !query.isEmpty else { return [] }
        let q = VectorMath.normalized(query)
        let scored = centroids.enumerated().map { (i, c) in (i, VectorMath.dot(q, c)) }
        let top = scored.sorted { $0.1 > $1.1 }.prefix(max(1, nprobe)).map { $0.0 }
        return Set(top)
    }

    /// Bucket for a single vector (nearest centroid) — used to assign new chunks.
    func bucket(for vector: [Float]) -> Int { Self.nearestCentroid(vector, centroids) }

    /// Nearest-centroid index for a (possibly un-normalized) vector. Static + value-typed
    /// so it can be handed to an off-main assignment pass without capturing the index.
    static func nearestCentroid(_ vector: [Float], _ centroids: [[Float]]) -> Int {
        guard !centroids.isEmpty else { return -1 }
        let v = VectorMath.normalized(vector)
        var best = -1; var bestScore = -Float.greatestFiniteMagnitude
        for (i, c) in centroids.enumerated() {
            let s = VectorMath.dot(v, c)
            if s > bestScore { bestScore = s; best = i }
        }
        return best
    }

    // MARK: - Build (spherical k-means on a sample)

    /// Pure k-means over a sample → centroids. Runs off-main; returns [] when there are
    /// too few vectors to cluster (caller then keeps the exact-scan fallback).
    static func computeCentroids(sample: [[Float]], nlist: Int, iterations: Int = 10) -> [[Float]] {
        let normalized = sample.map { VectorMath.normalized($0) }.filter { !$0.isEmpty }
        guard nlist > 0, normalized.count >= nlist else { return [] }
        return kmeans(normalized, k: nlist, iterations: iterations)
    }

    /// Install freshly-computed centroids (on the main actor) and persist them.
    func install(centroids: [[Float]], totalChunks: Int) {
        self.centroids = centroids
        self.builtChunkCount = totalChunks
        save()
    }

    /// Whether a rebuild is worthwhile given the current embedded-chunk count.
    func needsRebuild(currentChunks: Int, minChunks: Int) -> Bool {
        guard currentChunks >= minChunks else { return false }   // small vault → exact scan
        if !isBuilt { return true }
        // Rebuild once the store has grown materially since the last build.
        return currentChunks > Int(Double(builtChunkCount) * 1.5) + 1000
    }

    private static func kmeans(_ data: [[Float]], k: Int, iterations: Int) -> [[Float]] {
        let dim = data[0].count
        // Deterministic spread-out seeding: evenly strided picks.
        var centroids: [[Float]] = []
        let stride = max(1, data.count / k)
        var idx = 0
        while centroids.count < k && idx < data.count { centroids.append(data[idx]); idx += stride }
        while centroids.count < k { centroids.append(data[centroids.count % data.count]) }

        for _ in 0..<iterations {
            var sums = Array(repeating: [Float](repeating: 0, count: dim), count: k)
            var counts = [Int](repeating: 0, count: k)
            for v in data {
                var best = 0; var bestScore = -Float.greatestFiniteMagnitude
                for c in 0..<k {
                    let s = VectorMath.dot(v, centroids[c])
                    if s > bestScore { bestScore = s; best = c }
                }
                counts[best] += 1
                var acc = sums[best]
                for d in 0..<dim { acc[d] += v[d] }
                sums[best] = acc
            }
            for c in 0..<k where counts[c] > 0 {
                var mean = sums[c]
                let inv = 1 / Float(counts[c])
                for d in 0..<dim { mean[d] *= inv }
                centroids[c] = VectorMath.normalized(mean)
            }
        }
        return centroids
    }

    // MARK: - Persistence (simple binary sidecar)

    private var fileURL: URL { AppPaths.annDir.appendingPathComponent("\(projectID.uuidString).idx") }

    private func save() {
        guard isBuilt else { return }
        var data = Data()
        func appendInt32(_ v: Int32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        appendInt32(1)                              // format version
        appendInt32(Int32(builtChunkCount))
        appendInt32(Int32(centroids.count))
        appendInt32(Int32(centroids.first?.count ?? 0))
        for c in centroids {
            for f in c { var x = f.bitPattern.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL), data.count >= 16 else { return }
        var offset = 0
        func readInt32() -> Int32 {
            defer { offset += 4 }
            return data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: Int32.self).littleEndian }
        }
        _ = readInt32()                              // version
        builtChunkCount = Int(readInt32())
        let n = Int(readInt32())
        let dim = Int(readInt32())
        guard n > 0, dim > 0, data.count >= 16 + n * dim * 4 else { centroids = []; return }
        var result: [[Float]] = []
        result.reserveCapacity(n)
        for _ in 0..<n {
            var v = [Float](repeating: 0, count: dim)
            for d in 0..<dim {
                let bits = data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
                v[d] = Float(bitPattern: bits); offset += 4
            }
            result.append(v)
        }
        centroids = result
    }

    /// Remove the on-disk index (e.g. on wipe / reset).
    func delete() {
        centroids = []; builtChunkCount = 0
        try? FileManager.default.removeItem(at: fileURL)
    }
}
