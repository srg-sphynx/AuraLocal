import Foundation

/// Measures exactly what Aura keeps on disk, so the user can see there's no mystery
/// junk — and reclaim it. Everything Aura writes lives under `AppPaths.appSupport`
/// (plus a custom vector-store path if the user set one); there are no scattered
/// caches elsewhere.
enum StorageInfo {

    struct Report: Equatable {
        var index: Int64      // vector store: sqlite (+ -wal / -shm)
        var fastCache: Int64  // ANN sidecar files (regenerable speed cache)
        var chats: Int64      // sessions.json
        var meta: Int64       // projects.json + settings.json
        var total: Int64      // everything under the app-support directory

        /// Storage not accounted for by the named line items (e.g. the custom
        /// vector-store file when it lives outside app-support).
        var other: Int64{ max(0, total - index - fastCache - chats - meta) }
    }

    /// Snapshot current on-disk usage. `databaseURL` is passed in because the vector
    /// store can be relocated (Settings → Vector Store Path).
    static func snapshot(databaseURL: URL) -> Report {
        let support = AppPaths.appSupport
        return Report(
            index: dbFamilySize(databaseURL),
            fastCache: dirSize(AppPaths.annDir),
            chats: fileSize(AppPaths.sessionsFile),
            meta: fileSize(AppPaths.projectsFile) + fileSize(AppPaths.settingsFile),
            total: dirSize(support) + dbFamilySizeIfOutside(databaseURL, support: support))
    }

    // MARK: - Sizing helpers

    /// A SQLite database is a family of files: the main file plus its `-wal` and `-shm`
    /// sidecars while open in WAL mode. Count all three.
    static func dbFamilySize(_ dbURL: URL) -> Int64 {
        ["", "-wal", "-shm"].reduce(0) { $0 + fileSize(URL(fileURLWithPath: dbURL.path + $1)) }
    }

    /// If the store was relocated outside app-support, its size isn't in the folder
    /// walk — add it so `total` stays honest.
    private static func dbFamilySizeIfOutside(_ dbURL: URL, support: URL) -> Int64 {
        dbURL.path.hasPrefix(support.path) ? 0 : dbFamilySize(dbURL)
    }

    static func fileSize(_ url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
    }

    /// Recursive byte size of a directory (skips nothing; symlinks not followed).
    static func dirSize(_ url: URL) -> Int64 {
        guard let en = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles], errorHandler: nil) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in en {
            let v = try? f.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if v?.isRegularFile == true { total += Int64(v?.fileSize ?? 0) }
        }
        return total
    }

    static func humanized(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }
}
