//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import Foundation
import CSQLite

/// Thin SQLite wrapper backing the on-device vector store, chunk metadata, a
/// keyword (FTS5) recall layer, and per-file index state.
///
/// Design notes for scale (32k+ files):
/// - Vectors are raw little-endian Float32 blobs; cosine is computed in Swift.
/// - A `files` table records a content hash + chunk-params hash + embed model per
///   file so re-scans **skip unchanged files** and a restart **never re-embeds**.
/// - Chunks can exist text-only (Smart Scan) and gain vectors lazily at query time.
/// - `chunks_fts` (a standalone FTS5 table) gives BM25 keyword recall with zero
///   model calls — the candidate pre-filter that keeps queries from loading every
///   vector into memory.
/// `@unchecked Sendable`: all access is serialized through the private `queue`,
/// so the handle can be safely used from the off-main indexing task.
final class AppDatabase: @unchecked Sendable {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.aura.local.db")
    static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self) // SQLITE_TRANSIENT

    init(path: URL) throws {
        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(path.path, &handle,
                                 SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard rc == SQLITE_OK, let handle else {
            throw DBError.open(String(cString: sqlite3_errstr(rc)))
        }
        self.db = handle
        try migrate()
    }

    deinit { if let db { sqlite3_close_v2(db) } }

    enum DBError: Error { case open(String), prepare(String), step(String) }

    // MARK: - Schema / migration

    private func migrate() throws {
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA synchronous=NORMAL;")
        // Performance tuning for large stores (888k+ chunks): a bigger page cache,
        // memory-mapped reads for the vector scan, and in-memory temp tables.
        try? exec("PRAGMA cache_size=-40000;")     // ~40 MB page cache
        try? exec("PRAGMA mmap_size=536870912;")   // 512 MB memory-mapped I/O
        try? exec("PRAGMA temp_store=MEMORY;")
        try exec("""
        CREATE TABLE IF NOT EXISTS chunks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id TEXT NOT NULL,
            file_path TEXT NOT NULL,
            file_name TEXT NOT NULL,
            heading TEXT,
            ordinal INTEGER NOT NULL,
            text TEXT NOT NULL,
            tags TEXT,
            token_estimate INTEGER NOT NULL DEFAULT 0,
            dim INTEGER NOT NULL DEFAULT 0,
            embedding BLOB,
            embed_model TEXT,
            text_hash TEXT
        );
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_chunks_project ON chunks(project_id);")
        try exec("CREATE INDEX IF NOT EXISTS idx_chunks_file ON chunks(project_id, file_path);")

        // Per-file index state (incremental skip + inventory rebuild on launch).
        try exec("""
        CREATE TABLE IF NOT EXISTS files (
            project_id TEXT NOT NULL,
            rel_path TEXT NOT NULL,
            file_name TEXT NOT NULL,
            ext TEXT,
            byte_size INTEGER NOT NULL DEFAULT 0,
            mtime REAL NOT NULL DEFAULT 0,
            content_hash TEXT,
            chunk_params_hash TEXT,
            embed_model TEXT,
            embed_dim INTEGER NOT NULL DEFAULT 0,
            chunk_count INTEGER NOT NULL DEFAULT 0,
            embedded_chunk_count INTEGER NOT NULL DEFAULT 0,
            token_estimate INTEGER NOT NULL DEFAULT 0,
            status TEXT,
            tags TEXT,
            aliases TEXT,
            last_indexed_at REAL NOT NULL DEFAULT 0,
            PRIMARY KEY (project_id, rel_path)
        );
        """)

        // Keyword recall layer. Standalone (not external-content) for robust sync:
        // searchable text columns + UNINDEXED metadata we filter/return.
        try exec("""
        CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
            text, heading, file_name, tags,
            project_id UNINDEXED, file_path UNINDEXED, chunk_id UNINDEXED,
            tokenize = 'unicode61 remove_diacritics 2'
        );
        """)

        // Upgrade older databases that predate the new columns.
        if !columnExists(table: "chunks", column: "embed_model") {
            try? exec("ALTER TABLE chunks ADD COLUMN embed_model TEXT;")
        }
        if !columnExists(table: "chunks", column: "text_hash") {
            try? exec("ALTER TABLE chunks ADD COLUMN text_hash TEXT;")
        }

        // v3: vectors are now stored as Float16 (were Float32). Any vector written
        // by an older build is byte-incompatible, so drop it — the text/FTS rows are
        // kept and the chunk is re-embedded on the next indexing pass.
        if userVersion() < 3 {
            try? exec("UPDATE chunks SET embedding=NULL, dim=0, embed_model=NULL;")
        }

        // v4: per-file diagnostics — why a file failed to index, plus a display title
        // extracted from the document (used by the Knowledge Base / Issues list).
        if !columnExists(table: "files", column: "error_message") {
            try? exec("ALTER TABLE files ADD COLUMN error_message TEXT;")
        }
        if !columnExists(table: "files", column: "title") {
            try? exec("ALTER TABLE files ADD COLUMN title TEXT;")
        }
        // v4: ANN coarse-quantization bucket per chunk. -1 = unassigned (always probed,
        // so newly-embedded chunks are never missed before the next index rebuild).
        if !columnExists(table: "chunks", column: "bucket") {
            try? exec("ALTER TABLE chunks ADD COLUMN bucket INTEGER NOT NULL DEFAULT -1;")
        }
        try? exec("CREATE INDEX IF NOT EXISTS idx_chunks_bucket ON chunks(project_id, bucket);")
        try? exec("PRAGMA user_version=4;")
    }

    private func userVersion() -> Int {
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(stmt) }
            return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
        }
    }

    private func columnExists(table: String, column: String) -> Bool {
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &stmt, nil) == SQLITE_OK else { return false }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 1), String(cString: c) == column { return true }
            }
            return false
        }
    }

    private func exec(_ sql: String) throws {
        try queue.sync {
            var err: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
                let msg = err.map { String(cString: $0) } ?? "unknown"
                sqlite3_free(err)
                throw DBError.step(msg)
            }
        }
    }

    // MARK: - Chunk writes

    /// Replace all chunks for a given file (used on (re)index). Keeps the FTS
    /// mirror in sync in the same transaction.
    func replaceChunks(projectID: UUID, filePath: String, fileName: String, rows: [ChunkRow]) throws {
        try queue.sync {
            try _exec("BEGIN;")
            defer { try? _exec("COMMIT;") }

            try deleteFileChunksLocked(projectID: projectID, filePath: filePath)

            let sql = """
            INSERT INTO chunks (project_id,file_path,file_name,heading,ordinal,text,tags,token_estimate,dim,embedding,embed_model,text_hash)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?);
            """
            var ins: OpaquePointer?
            try prepare(sql, &ins)
            defer { sqlite3_finalize(ins) }

            var ftsIns: OpaquePointer?
            try prepare("INSERT INTO chunks_fts (text,heading,file_name,tags,project_id,file_path,chunk_id) VALUES (?,?,?,?,?,?,?);", &ftsIns)
            defer { sqlite3_finalize(ftsIns) }

            for r in rows {
                sqlite3_reset(ins)
                bindText(ins, 1, projectID.uuidString)
                bindText(ins, 2, filePath)
                bindText(ins, 3, fileName)
                if let h = r.heading { bindText(ins, 4, h) } else { sqlite3_bind_null(ins, 4) }
                sqlite3_bind_int64(ins, 5, Int64(r.ordinal))
                bindText(ins, 6, r.text)
                bindText(ins, 7, r.tags.joined(separator: ","))
                sqlite3_bind_int64(ins, 8, Int64(r.tokenEstimate))
                sqlite3_bind_int64(ins, 9, Int64(r.embedding.count))
                if r.embedding.isEmpty {
                    sqlite3_bind_null(ins, 10)
                } else {
                    let blob = VectorMath.encodeF16(r.embedding)
                    blob.withUnsafeBytes { raw in
                        _ = sqlite3_bind_blob(ins, 10, raw.baseAddress, Int32(raw.count), AppDatabase.transient)
                    }
                }
                if r.embedding.isEmpty || r.embedModel.isEmpty { sqlite3_bind_null(ins, 11) } else { bindText(ins, 11, r.embedModel) }
                bindText(ins, 12, r.textHash)
                stepDone(ins)

                let chunkID = sqlite3_last_insert_rowid(db)
                sqlite3_reset(ftsIns)
                bindText(ftsIns, 1, r.text)
                bindText(ftsIns, 2, r.heading ?? "")
                bindText(ftsIns, 3, fileName)
                bindText(ftsIns, 4, r.tags.joined(separator: " "))
                bindText(ftsIns, 5, projectID.uuidString)
                bindText(ftsIns, 6, filePath)
                sqlite3_bind_int64(ftsIns, 7, chunkID)
                stepDone(ftsIns)
            }
        }
    }

    /// Persist freshly-computed vectors for specific chunk ids (lazy embedding).
    func updateChunkVectors(_ updates: [(id: Int64, vector: [Float], model: String)]) throws {
        guard !updates.isEmpty else { return }
        try queue.sync {
            try _exec("BEGIN;")
            defer { try? _exec("COMMIT;") }
            var stmt: OpaquePointer?
            try prepare("UPDATE chunks SET embedding=?, dim=?, embed_model=? WHERE id=?;", &stmt)
            defer { sqlite3_finalize(stmt) }
            for u in updates {
                sqlite3_reset(stmt)
                if u.vector.isEmpty {
                    sqlite3_bind_null(stmt, 1)
                } else {
                    let blob = VectorMath.encodeF16(u.vector)
                    blob.withUnsafeBytes { raw in
                        _ = sqlite3_bind_blob(stmt, 1, raw.baseAddress, Int32(raw.count), AppDatabase.transient)
                    }
                }
                sqlite3_bind_int64(stmt, 2, Int64(u.vector.count))
                bindText(stmt, 3, u.model)
                sqlite3_bind_int64(stmt, 4, u.id)
                stepDone(stmt)
            }
        }
    }

    func deleteFile(projectID: UUID, filePath: String) throws {
        try queue.sync {
            try _exec("BEGIN;")
            defer { try? _exec("COMMIT;") }
            try deleteFileChunksLocked(projectID: projectID, filePath: filePath)
            var del: OpaquePointer?
            try prepare("DELETE FROM files WHERE project_id=? AND rel_path=?;", &del)
            bindText(del, 1, projectID.uuidString); bindText(del, 2, filePath)
            stepDone(del); sqlite3_finalize(del)
        }
    }

    func deleteProject(_ projectID: UUID) throws {
        try queue.sync {
            for table in ["chunks", "chunks_fts", "files"] {
                let col = table == "files" ? "project_id" : "project_id"
                var del: OpaquePointer?
                try prepare("DELETE FROM \(table) WHERE \(col)=?;", &del)
                bindText(del, 1, projectID.uuidString)
                stepDone(del); sqlite3_finalize(del)
            }
        }
    }

    /// Must be called inside `queue` (and usually inside a transaction).
    private func deleteFileChunksLocked(projectID: UUID, filePath: String) throws {
        for table in ["chunks", "chunks_fts"] {
            var del: OpaquePointer?
            try prepare("DELETE FROM \(table) WHERE project_id=? AND file_path=?;", &del)
            bindText(del, 1, projectID.uuidString)
            bindText(del, 2, filePath)
            stepDone(del); sqlite3_finalize(del)
        }
    }

    // MARK: - File state (incremental index)

    func upsertFileState(_ f: FileState) {
        queue.sync {
            var stmt: OpaquePointer?
            let sql = """
            INSERT OR REPLACE INTO files
            (project_id,rel_path,file_name,ext,byte_size,mtime,content_hash,chunk_params_hash,embed_model,embed_dim,chunk_count,embedded_chunk_count,token_estimate,status,tags,aliases,last_indexed_at,error_message,title)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
            """
            guard (try? prepare(sql, &stmt)) != nil else { return }
            bindText(stmt, 1, f.projectID.uuidString)
            bindText(stmt, 2, f.relPath)
            bindText(stmt, 3, f.fileName)
            bindText(stmt, 4, f.ext)
            sqlite3_bind_int64(stmt, 5, f.byteSize)
            sqlite3_bind_double(stmt, 6, f.mtime)
            bindText(stmt, 7, f.contentHash)
            bindText(stmt, 8, f.chunkParamsHash)
            bindText(stmt, 9, f.embedModel)
            sqlite3_bind_int64(stmt, 10, Int64(f.embedDim))
            sqlite3_bind_int64(stmt, 11, Int64(f.chunkCount))
            sqlite3_bind_int64(stmt, 12, Int64(f.embeddedChunkCount))
            sqlite3_bind_int64(stmt, 13, Int64(f.tokenEstimate))
            bindText(stmt, 14, f.status)
            bindText(stmt, 15, f.tags.joined(separator: ","))
            bindText(stmt, 16, f.aliases.joined(separator: ","))
            sqlite3_bind_double(stmt, 17, f.lastIndexedAt)
            if let e = f.errorMessage, !e.isEmpty { bindText(stmt, 18, e) } else { sqlite3_bind_null(stmt, 18) }
            if let t = f.title, !t.isEmpty { bindText(stmt, 19, t) } else { sqlite3_bind_null(stmt, 19) }
            stepDone(stmt); sqlite3_finalize(stmt)
        }
    }

    func loadFileStates(projectID: UUID) -> [FileState] {
        queue.sync {
            var stmt: OpaquePointer?
            let sql = "SELECT rel_path,file_name,ext,byte_size,mtime,content_hash,chunk_params_hash,embed_model,embed_dim,chunk_count,embedded_chunk_count,token_estimate,status,tags,aliases,last_indexed_at,error_message,title FROM files WHERE project_id=?;"
            guard (try? prepare(sql, &stmt)) != nil else { return [] }
            bindText(stmt, 1, projectID.uuidString)
            var out: [FileState] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(FileState(
                    projectID: projectID,
                    relPath: columnText(stmt, 0),
                    fileName: columnText(stmt, 1),
                    ext: columnText(stmt, 2),
                    byteSize: sqlite3_column_int64(stmt, 3),
                    mtime: sqlite3_column_double(stmt, 4),
                    contentHash: columnText(stmt, 5),
                    chunkParamsHash: columnText(stmt, 6),
                    embedModel: columnText(stmt, 7),
                    embedDim: Int(sqlite3_column_int64(stmt, 8)),
                    chunkCount: Int(sqlite3_column_int64(stmt, 9)),
                    embeddedChunkCount: Int(sqlite3_column_int64(stmt, 10)),
                    tokenEstimate: Int(sqlite3_column_int64(stmt, 11)),
                    status: columnText(stmt, 12),
                    tags: splitCSV(columnText(stmt, 13)),
                    aliases: splitCSV(columnText(stmt, 14)),
                    lastIndexedAt: sqlite3_column_double(stmt, 15),
                    errorMessage: columnTextOpt(stmt, 16),
                    title: columnTextOpt(stmt, 17)))
            }
            sqlite3_finalize(stmt)
            return out
        }
    }

    /// Remove files (and their chunks/FTS rows) whose rel_path is no longer present
    /// on disk. Returns the deleted paths so the caller can update its inventory.
    @discardableResult
    func deleteMissingFiles(projectID: UUID, keep: Set<String>) -> [String] {
        let existing = loadFileStates(projectID: projectID).map { $0.relPath }
        let missing = existing.filter { !keep.contains($0) }
        for path in missing { try? deleteFile(projectID: projectID, filePath: path) }
        return missing
    }

    // MARK: - Reads

    func chunkCount(projectID: UUID) -> Int { count("SELECT COUNT(*) FROM chunks WHERE project_id=?;", projectID) }
    func embeddedChunkCount(projectID: UUID) -> Int { count("SELECT COUNT(*) FROM chunks WHERE project_id=? AND embedding IS NOT NULL;", projectID) }

    private func count(_ sql: String, _ projectID: UUID) -> Int {
        queue.sync {
            var stmt: OpaquePointer?
            guard (try? prepare(sql, &stmt)) != nil else { return 0 }
            bindText(stmt, 1, projectID.uuidString)
            var n = 0
            if sqlite3_step(stmt) == SQLITE_ROW { n = Int(sqlite3_column_int64(stmt, 0)) }
            sqlite3_finalize(stmt)
            return n
        }
    }

    func totalChunkCount() -> Int {
        queue.sync {
            var stmt: OpaquePointer?
            guard (try? prepare("SELECT COUNT(*) FROM chunks;", &stmt)) != nil else { return 0 }
            var n = 0
            if sqlite3_step(stmt) == SQLITE_ROW { n = Int(sqlite3_column_int64(stmt, 0)) }
            sqlite3_finalize(stmt)
            return n
        }
    }

    /// BM25 keyword candidates for a query, best match first. `rank` is SQLite's
    /// bm25 value (more negative = better); we return it as `score` for fusion.
    func ftsCandidates(projectID: UUID, query: String, limit: Int) -> [FTSCandidate] {
        guard let match = Self.makeMatchExpression(query) else { return [] }
        return queue.sync {
            var stmt: OpaquePointer?
            let sql = "SELECT chunk_id, file_path, rank FROM chunks_fts WHERE chunks_fts MATCH ? AND project_id = ? ORDER BY rank LIMIT ?;"
            guard (try? prepare(sql, &stmt)) != nil else { return [] }
            bindText(stmt, 1, match)
            bindText(stmt, 2, projectID.uuidString)
            sqlite3_bind_int64(stmt, 3, Int64(limit))
            var out: [FTSCandidate] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(FTSCandidate(chunkID: sqlite3_column_int64(stmt, 0),
                                        filePath: columnText(stmt, 1),
                                        bm25: sqlite3_column_double(stmt, 2)))
            }
            sqlite3_finalize(stmt)
            return out
        }
    }

    /// Load full chunk rows (incl. any stored vector) for specific ids.
    func chunksByIDs(_ ids: [Int64]) -> [EmbeddedChunk] {
        guard !ids.isEmpty else { return [] }
        return queue.sync {
            let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
            let sql = "SELECT id,file_name,file_path,heading,text,tags,dim,embedding,embed_model,ordinal FROM chunks WHERE id IN (\(placeholders));"
            var stmt: OpaquePointer?
            guard (try? prepare(sql, &stmt)) != nil else { return [] }
            for (i, id) in ids.enumerated() { sqlite3_bind_int64(stmt, Int32(i + 1), id) }
            var out: [EmbeddedChunk] = []
            while sqlite3_step(stmt) == SQLITE_ROW { out.append(readEmbeddedChunk(stmt)) }
            sqlite3_finalize(stmt)
            return out
        }
    }

    /// Pure-semantic recall: stream every stored vector for the project (matching the
    /// query's dimensionality), score cosine against `queryVector`, and return the top
    /// `k` chunk ids. Rows are decoded one at a time so peak memory is O(k), not the
    /// whole vector store — safe at 32k+ files. Only scalar scores are retained.
    func semanticTopK(projectID: UUID, queryVector: [Float], k: Int) -> [(chunkID: Int64, cos: Double)] {
        guard !queryVector.isEmpty, k > 0 else { return [] }
        return queue.sync {
            var stmt: OpaquePointer?
            let sql = "SELECT id, dim, embedding FROM chunks WHERE project_id=? AND embedding IS NOT NULL AND dim=?;"
            guard (try? prepare(sql, &stmt)) != nil else { return [] }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, projectID.uuidString)
            sqlite3_bind_int64(stmt, 2, Int64(queryVector.count))
            var scored: [(Int64, Double)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let dim = Int(sqlite3_column_int64(stmt, 1))
                guard dim == queryVector.count, let blob = sqlite3_column_blob(stmt, 2) else { continue }
                let bytes = Int(sqlite3_column_bytes(stmt, 2))
                let vec = VectorMath.decodeF16(blob, byteCount: bytes, dim: dim)
                scored.append((id, Double(VectorMath.cosine(queryVector, vec))))
            }
            scored.sort { $0.1 > $1.1 }
            return scored.prefix(k).map { (chunkID: $0.0, cos: $0.1) }
        }
    }

    /// ANN-accelerated semantic recall: like `semanticTopK` but only scans chunks whose
    /// coarse-quantization `bucket` is in `buckets` (plus bucket -1, the always-probed
    /// unassigned set). Cuts the per-query vector read from O(N) to O(N·nprobe/nlist).
    func semanticTopKInBuckets(projectID: UUID, queryVector: [Float], buckets: Set<Int>, k: Int) -> [(chunkID: Int64, cos: Double)] {
        guard !queryVector.isEmpty, k > 0, !buckets.isEmpty else { return [] }
        return queue.sync {
            var probed = buckets; probed.insert(-1)
            let placeholders = probed.map { _ in "?" }.joined(separator: ",")
            let sql = "SELECT id, dim, embedding FROM chunks WHERE project_id=? AND embedding IS NOT NULL AND dim=? AND bucket IN (\(placeholders));"
            var stmt: OpaquePointer?
            guard (try? prepare(sql, &stmt)) != nil else { return [] }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, projectID.uuidString)
            sqlite3_bind_int64(stmt, 2, Int64(queryVector.count))
            for (i, b) in probed.enumerated() { sqlite3_bind_int64(stmt, Int32(3 + i), Int64(b)) }
            var scored: [(Int64, Double)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let dim = Int(sqlite3_column_int64(stmt, 1))
                guard dim == queryVector.count, let blob = sqlite3_column_blob(stmt, 2) else { continue }
                let bytes = Int(sqlite3_column_bytes(stmt, 2))
                let vec = VectorMath.decodeF16(blob, byteCount: bytes, dim: dim)
                scored.append((id, Double(VectorMath.cosine(queryVector, vec))))
            }
            scored.sort { $0.1 > $1.1 }
            return scored.prefix(k).map { (chunkID: $0.0, cos: $0.1) }
        }
    }

    /// Chunks adjacent to `ordinal` within the same file (parent-document / small-to-big
    /// expansion). Ordered by ordinal; vectors are not needed by the caller.
    func neighborChunks(projectID: UUID, filePath: String, ordinal: Int, radius: Int) -> [EmbeddedChunk] {
        guard radius > 0 else { return [] }
        return queue.sync {
            var stmt: OpaquePointer?
            let sql = "SELECT id,file_name,file_path,heading,text,tags,dim,embedding,embed_model,ordinal FROM chunks WHERE project_id=? AND file_path=? AND ordinal BETWEEN ? AND ? ORDER BY ordinal;"
            guard (try? prepare(sql, &stmt)) != nil else { return [] }
            bindText(stmt, 1, projectID.uuidString)
            bindText(stmt, 2, filePath)
            sqlite3_bind_int64(stmt, 3, Int64(ordinal - radius))
            sqlite3_bind_int64(stmt, 4, Int64(ordinal + radius))
            var out: [EmbeddedChunk] = []
            while sqlite3_step(stmt) == SQLITE_ROW { out.append(readEmbeddedChunk(stmt)) }
            sqlite3_finalize(stmt)
            return out
        }
    }

    // MARK: - ANN index build support

    /// A bounded sample of embedded vectors (for k-means centroid seeding).
    func sampleVectors(projectID: UUID, limit: Int) -> [[Float]] {
        guard limit > 0 else { return [] }
        return queue.sync {
            var stmt: OpaquePointer?
            let sql = "SELECT dim, embedding FROM chunks WHERE project_id=? AND embedding IS NOT NULL LIMIT ?;"
            guard (try? prepare(sql, &stmt)) != nil else { return [] }
            bindText(stmt, 1, projectID.uuidString)
            sqlite3_bind_int64(stmt, 2, Int64(limit))
            var out: [[Float]] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let dim = Int(sqlite3_column_int64(stmt, 0))
                guard dim > 0, let blob = sqlite3_column_blob(stmt, 1) else { continue }
                let bytes = Int(sqlite3_column_bytes(stmt, 1))
                out.append(VectorMath.decodeF16(blob, byteCount: bytes, dim: dim))
            }
            sqlite3_finalize(stmt)
            return out
        }
    }

    /// Stream every embedded vector for the project, assign it to a bucket via `assign`,
    /// and persist the bucket. Returns the number of chunks (re)assigned. One-time cost
    /// after a full embedding pass; streamed so peak memory stays O(1).
    @discardableResult
    func assignBuckets(projectID: UUID, assign: ([Float]) -> Int) -> Int {
        queue.sync {
            // Collect (id -> bucket) by streaming vectors, then batch-update.
            var sel: OpaquePointer?
            let selSQL = "SELECT id, dim, embedding FROM chunks WHERE project_id=? AND embedding IS NOT NULL;"
            guard (try? prepare(selSQL, &sel)) != nil else { return 0 }
            bindText(sel, 1, projectID.uuidString)
            var assignments: [(Int64, Int)] = []
            while sqlite3_step(sel) == SQLITE_ROW {
                let id = sqlite3_column_int64(sel, 0)
                let dim = Int(sqlite3_column_int64(sel, 1))
                guard dim > 0, let blob = sqlite3_column_blob(sel, 2) else { continue }
                let bytes = Int(sqlite3_column_bytes(sel, 2))
                let vec = VectorMath.decodeF16(blob, byteCount: bytes, dim: dim)
                assignments.append((id, assign(vec)))
            }
            sqlite3_finalize(sel)
            guard !assignments.isEmpty else { return 0 }

            try? _exec("BEGIN;")
            var upd: OpaquePointer?
            if (try? prepare("UPDATE chunks SET bucket=? WHERE id=?;", &upd)) != nil {
                for (id, bucket) in assignments {
                    sqlite3_reset(upd)
                    sqlite3_bind_int64(upd, 1, Int64(bucket))
                    sqlite3_bind_int64(upd, 2, id)
                    stepDone(upd)
                }
                sqlite3_finalize(upd)
            }
            try? _exec("COMMIT;")
            return assignments.count
        }
    }

    /// Delete every stored chunk, FTS row, and file record across all projects.
    /// Used by the "clear index" / factory-reset flow.
    func wipeAll() {
        queue.sync {
            for t in ["chunks", "chunks_fts", "files"] { try? _exec("DELETE FROM \(t);") }
            try? _exec("PRAGMA wal_checkpoint(TRUNCATE);")
            try? _exec("VACUUM;")
        }
    }

    /// Reclaim disk space left behind by deletions: checkpoint the WAL back into the main
    /// file, then VACUUM to release free pages (SQLite never shrinks a file on its own).
    /// O(database size), so call it after bulk removals — not on every small delete.
    func compact() {
        queue.sync {
            try? _exec("PRAGMA wal_checkpoint(TRUNCATE);")
            try? _exec("VACUUM;")
        }
    }

    /// Chunks lacking a vector for `model` — drives the full-mode embedding pass.
    func chunksNeedingEmbedding(projectID: UUID, model: String, limit: Int) -> [(id: Int64, text: String)] {
        queue.sync {
            var stmt: OpaquePointer?
            let sql = "SELECT id, text FROM chunks WHERE project_id=? AND (embedding IS NULL OR embed_model IS NULL OR embed_model<>?) LIMIT ?;"
            guard (try? prepare(sql, &stmt)) != nil else { return [] }
            bindText(stmt, 1, projectID.uuidString)
            bindText(stmt, 2, model)
            sqlite3_bind_int64(stmt, 3, Int64(limit))
            var out: [(Int64, String)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append((sqlite3_column_int64(stmt, 0), columnText(stmt, 1)))
            }
            sqlite3_finalize(stmt)
            return out
        }
    }

    func countNeedingEmbedding(projectID: UUID, model: String) -> Int {
        queue.sync {
            var stmt: OpaquePointer?
            let sql = "SELECT COUNT(*) FROM chunks WHERE project_id=? AND (embedding IS NULL OR embed_model IS NULL OR embed_model<>?);"
            guard (try? prepare(sql, &stmt)) != nil else { return 0 }
            bindText(stmt, 1, projectID.uuidString)
            bindText(stmt, 2, model)
            var n = 0
            if sqlite3_step(stmt) == SQLITE_ROW { n = Int(sqlite3_column_int64(stmt, 0)) }
            sqlite3_finalize(stmt)
            return n
        }
    }

    private func readEmbeddedChunk(_ stmt: OpaquePointer?) -> EmbeddedChunk {
        let id = sqlite3_column_int64(stmt, 0)
        let fileName = columnText(stmt, 1)
        let filePath = columnText(stmt, 2)
        let heading = columnTextOpt(stmt, 3)
        let text = columnText(stmt, 4)
        let tags = splitCSV(columnText(stmt, 5))
        let dim = Int(sqlite3_column_int64(stmt, 6))
        var vec: [Float] = []
        if dim > 0, let blob = sqlite3_column_blob(stmt, 7) {
            let bytes = Int(sqlite3_column_bytes(stmt, 7))
            vec = VectorMath.decodeF16(blob, byteCount: bytes, dim: dim)
        }
        let embedModel = columnText(stmt, 8)
        let ordinal = Int(sqlite3_column_int64(stmt, 9))
        return EmbeddedChunk(id: id, fileName: fileName, filePath: filePath,
                             heading: heading, text: text, tags: tags, vector: vec,
                             embedModel: embedModel, ordinal: ordinal)
    }

    // MARK: - FTS query sanitation

    /// Turn arbitrary user text into a safe FTS5 MATCH expression: alphanumeric
    /// tokens, quoted, OR-joined. Avoids syntax errors from punctuation/operators.
    static func makeMatchExpression(_ raw: String) -> String? {
        let tokens = raw.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 }
        guard !tokens.isEmpty else { return nil }
        // De-dupe, cap to keep the query bounded.
        var seen = Set<String>(); var ordered: [String] = []
        for t in tokens where !seen.contains(t) { seen.insert(t); ordered.append(t) }
        return ordered.prefix(24).map { "\"\($0)\"" }.joined(separator: " OR ")
    }

    // MARK: - Private statement helpers (must be called inside `queue`)

    private func _exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"; sqlite3_free(err)
            throw DBError.step(msg)
        }
    }
    private func prepare(_ sql: String, _ stmt: inout OpaquePointer?) throws {
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw DBError.prepare(String(cString: sqlite3_errmsg(db)))
        }
    }
    private func bindText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String) {
        sqlite3_bind_text(stmt, idx, value, -1, AppDatabase.transient)
    }
    private func stepDone(_ stmt: OpaquePointer?) { _ = sqlite3_step(stmt) }
    private func columnText(_ stmt: OpaquePointer?, _ idx: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, idx) else { return "" }
        return String(cString: c)
    }
    private func columnTextOpt(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, idx) else { return nil }
        return String(cString: c)
    }
    private func splitCSV(_ s: String) -> [String] {
        s.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }
}

// MARK: - Row types

struct ChunkRow {
    var heading: String?
    var ordinal: Int
    var text: String
    var tags: [String]
    var tokenEstimate: Int
    var embedding: [Float]
    var textHash: String = ""
    var embedModel: String = ""
}

struct EmbeddedChunk {
    var id: Int64
    var fileName: String
    var filePath: String
    var heading: String?
    var text: String
    var tags: [String]
    var vector: [Float]
    var embedModel: String = ""
    var ordinal: Int = 0
}

struct FTSCandidate {
    var chunkID: Int64
    var filePath: String
    var bm25: Double   // SQLite rank: lower (more negative) = better
}

/// Persistent per-file index record (mirrors a row of the `files` table).
struct FileState {
    var projectID: UUID
    var relPath: String
    var fileName: String
    var ext: String
    var byteSize: Int64
    var mtime: Double
    var contentHash: String
    var chunkParamsHash: String
    var embedModel: String
    var embedDim: Int
    var chunkCount: Int
    var embeddedChunkCount: Int
    var tokenEstimate: Int
    var status: String
    var tags: [String]
    var aliases: [String]
    var lastIndexedAt: Double
    /// v4: why the file failed to index (nil when synced), and a display title.
    var errorMessage: String? = nil
    var title: String? = nil
}
