import Foundation

/// A per-chat **working set** of the sources already retrieved for the conversation,
/// kept in memory with their vectors so a follow-up question can be scored against
/// them instantly — no round trip to the vector store.
///
/// The point is the *fast path*: when a chat first indexes, say, 50 sources for a
/// question, the next question that lives inside those same sources should answer
/// immediately, without re-running the O(N) cosine scan over the whole vault. When a
/// question instead drifts to material *outside* the working set, coverage comes back
/// weak and the caller falls back to a full scan, then `merge`s the new sources back
/// in. So the cache only ever *adds* speed — it never caps recall.
///
/// `@MainActor` because it's driven from `IndexingService` (also main-actor). Scoring
/// a few hundred cached vectors is sub-millisecond, so there's no need to hop off.
@MainActor
final class SessionSourceCache {

    /// One cached chunk plus the bookkeeping used for eviction and recency.
    private struct Entry {
        var chunk: EmbeddedChunk     // carries the stored embedding vector
        var bestScore: Double        // best cosine this chunk has ever scored (eviction key)
        var lastTurn: Int            // last turn it was scored/merged (recency)
    }

    /// How well the current query is covered by a session's working set.
    struct Coverage {
        /// Every cached chunk paired with its cosine to the query, best first.
        var scored: [(chunk: EmbeddedChunk, cos: Double)]
        /// Highest cosine in the working set (0 when the set is empty / wrong project).
        var best: Double
        /// How many cached chunks clear the reuse threshold.
        var strongCount: Int
        var isEmpty: Bool { scored.isEmpty }
    }

    private struct Bucket {
        var projectID: UUID
        var entries: [Int64: Entry] = [:]
        var turn: Int = 0
    }

    private var buckets: [UUID: Bucket] = [:]     // sessionID → working set
    private let capacity: Int

    /// `capacity` bounds memory: at ~1k-dim f16→f32 vectors this is ~1 MB per chat.
    init(capacity: Int = 256) { self.capacity = capacity }

    // MARK: - Lifecycle

    /// Drop a chat's working set (new chat, chat deleted, or its vault changed).
    func reset(session: UUID) { buckets[session] = nil }

    func resetAll() { buckets.removeAll() }

    /// Number of cached sources for a chat (diagnostics / UI).
    func count(session: UUID) -> Int { buckets[session]?.entries.count ?? 0 }

    // MARK: - Query-time

    /// Score `queryVector` against a chat's cached chunks. Empty when there's no set
    /// for the chat, it belongs to a different vault, or dimensions don't match (e.g.
    /// the embedding model changed) — all of which correctly force a full scan.
    func coverage(session: UUID, project: UUID, queryVector: [Float],
                  reuseThreshold: Double) -> Coverage {
        guard let bucket = buckets[session], bucket.projectID == project,
              !bucket.entries.isEmpty, !queryVector.isEmpty else {
            return Coverage(scored: [], best: 0, strongCount: 0)
        }
        var scored: [(chunk: EmbeddedChunk, cos: Double)] = []
        scored.reserveCapacity(bucket.entries.count)
        for entry in bucket.entries.values where entry.chunk.vector.count == queryVector.count {
            let cos = Double(VectorMath.cosine(queryVector, entry.chunk.vector))
            scored.append((entry.chunk, cos))
        }
        scored.sort { $0.cos > $1.cos }
        let best = scored.first?.cos ?? 0
        let strong = scored.reduce(0) { $0 + ($1.cos >= reuseThreshold ? 1 : 0) }
        return Coverage(scored: scored, best: best, strongCount: strong)
    }

    /// Fold a freshly retrieved candidate pool into a chat's working set. Called after
    /// every full scan so the set tracks wherever the conversation has ranged. Advances
    /// the chat's turn counter and evicts the weakest entries back down to `capacity`.
    func merge(session: UUID, project: UUID, scored: [(chunk: EmbeddedChunk, cos: Double)]) {
        var bucket = buckets[session] ?? Bucket(projectID: project)
        // A vault switch invalidates the whole set (paths/vectors no longer comparable).
        if bucket.projectID != project { bucket = Bucket(projectID: project) }
        bucket.turn += 1
        let turn = bucket.turn

        for item in scored where !item.chunk.vector.isEmpty {
            if var existing = bucket.entries[item.chunk.id] {
                existing.bestScore = max(existing.bestScore, item.cos)
                existing.lastTurn = turn
                existing.chunk = item.chunk          // refresh (text/vector may be newer)
                bucket.entries[item.chunk.id] = existing
            } else {
                bucket.entries[item.chunk.id] = Entry(chunk: item.chunk, bestScore: item.cos, lastTurn: turn)
            }
        }

        evict(&bucket)
        buckets[session] = bucket
    }

    /// Note that these chunks grounded the latest answer, keeping them fresh so a run
    /// of follow-ups on the same material doesn't evict the very sources in play.
    func touch(session: UUID, ids: [Int64]) {
        guard var bucket = buckets[session] else { return }
        for id in ids where bucket.entries[id] != nil { bucket.entries[id]?.lastTurn = bucket.turn }
        buckets[session] = bucket
    }

    // MARK: - Eviction

    /// Keep the `capacity` most valuable entries. Value = best cosine ever scored,
    /// tie-broken by recency, so proven-relevant and recently-used sources survive.
    private func evict(_ bucket: inout Bucket) {
        guard bucket.entries.count > capacity else { return }
        let ranked = bucket.entries.values.sorted {
            $0.bestScore != $1.bestScore ? $0.bestScore > $1.bestScore : $0.lastTurn > $1.lastTurn
        }
        bucket.entries = Dictionary(uniqueKeysWithValues: ranked.prefix(capacity).map { ($0.chunk.id, $0) })
    }
}
