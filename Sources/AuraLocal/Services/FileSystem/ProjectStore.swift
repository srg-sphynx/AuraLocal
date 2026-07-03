import Foundation
import AppKit
import Combine

/// Manages user-selected vaults/projects: NSOpenPanel selection, security-scoped
/// bookmark persistence, and live file watching with auto re-index.
@MainActor
final class ProjectStore: ObservableObject {
    @Published var projects: [Project] = []
    @Published var selectedProjectID: UUID?

    private var watchers: [UUID: VaultWatcher] = [:]
    weak var indexingService: IndexingService?
    private unowned let settingsStore: SettingsStore

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        load()
    }

    var selectedProject: Project? {
        projects.first { $0.id == selectedProjectID }
    }

    /// Resolve a citation's vault by id, falling back to the current selection when
    /// the id is unknown (e.g. an older session saved before citations tracked it).
    func project(id: UUID?) -> Project? {
        if let id, let p = projects.first(where: { $0.id == id }) { return p }
        return selectedProject
    }

    // MARK: - Persistence

    private func load() {
        if let data = try? Data(contentsOf: AppPaths.projectsFile),
           let decoded = try? JSONDecoder().decode([Project].self, from: data) {
            projects = decoded
            selectedProjectID = decoded.first?.id
            for p in decoded { startWatching(p) }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(projects) {
            try? data.write(to: AppPaths.projectsFile, options: .atomic)
        }
    }

    // MARK: - Add via NSOpenPanel

    /// Presents an open panel for the user to pick an Obsidian / Markdown vault.
    func addVault(kind: VaultKind = .obsidian) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Vault"
        panel.message = "Choose your Obsidian or Markdown vault folder. Aura keeps persistent access via a security-scoped bookmark."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.register(url: url, kind: kind)
        }
    }

    private func register(url: URL, kind: VaultKind) {
        do {
            let bookmark = try BookmarkStore.makeBookmark(for: url)
            // Detect Obsidian vault by presence of .obsidian dir.
            let isObsidian = FileManager.default.fileExists(
                atPath: url.appendingPathComponent(".obsidian").path)
            var project = Project(name: url.lastPathComponent,
                                  kind: isObsidian ? .obsidian : kind,
                                  path: url.path,
                                  bookmark: bookmark)
            project.status = .pending
            project.indexMode = settingsStore.settings.indexModeDefault
            projects.append(project)
            selectedProjectID = project.id
            save()
            startWatching(project)
            // Incremental scan (skips unchanged files) followed by the full embedding pass.
            indexingService?.index(project: project)
        } catch {
            NSLog("Aura: failed to bookmark vault: \(error)")
        }
    }

    func removeProject(_ project: Project) {
        stopWatching(project.id)
        projects.removeAll { $0.id == project.id }
        if selectedProjectID == project.id { selectedProjectID = projects.first?.id }
        save()
        Task { @MainActor in
            indexingService?.indexedFiles[project.id] = nil
        }
    }

    /// Remove every vault (watchers + registrations). Used by the reset flow. The
    /// caller is responsible for wiping the vector store and the on-disk projects file.
    func removeAllProjects() {
        stopAll()
        watchers.removeAll()
        projects.removeAll()
        selectedProjectID = nil
        save()
    }

    func reindex(_ project: Project, force: Bool = false) {
        indexingService?.index(project: project, force: force)
    }

    func updateStatus(_ projectID: UUID, status: IndexStatus) {
        guard let i = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[i].status = status
        save()
    }

    // MARK: - Watching

    private func startWatching(_ project: Project) {
        guard settingsStore.settings.autoRefreshOnSave else { return }
        guard let url = try? BookmarkStore.resolve(project.bookmark).url else { return }
        _ = url.startAccessingSecurityScopedResource()
        let watcher = VaultWatcher(rootURL: url) { [weak self] rel in
            guard let self else { return }
            Task { @MainActor in
                if let p = self.projects.first(where: { $0.id == project.id }) {
                    self.indexingService?.reindexFile(project: p, relativePath: rel)
                }
            }
        }
        watcher.start()
        watchers[project.id] = watcher
    }

    private func stopWatching(_ id: UUID) {
        watchers[id]?.stop()
        watchers[id] = nil
    }

    func stopAll() { watchers.values.forEach { $0.stop() } }
}
