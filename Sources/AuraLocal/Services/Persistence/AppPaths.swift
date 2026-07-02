import Foundation

enum AppPaths {
    static let bundleID = "com.aura.local"

    static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("AuraLocal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var settingsFile: URL { appSupport.appendingPathComponent("settings.json") }
    static var sessionsFile: URL { appSupport.appendingPathComponent("sessions.json") }
    static var projectsFile: URL { appSupport.appendingPathComponent("projects.json") }
    static var defaultDatabaseFile: URL { appSupport.appendingPathComponent("aura_vectors.sqlite") }

    /// Sidecar directory holding per-project ANN index files (centroids).
    static var annDir: URL {
        let dir = appSupport.appendingPathComponent("ann", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Every removable app-data file (JSON state). The SQLite vector store is emptied
    /// via `AppDatabase.wipeAll()` rather than deleted, since its handle stays open.
    static var allDataFiles: [URL] { [settingsFile, sessionsFile, projectsFile] }
}
