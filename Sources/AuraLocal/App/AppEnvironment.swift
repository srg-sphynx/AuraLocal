import Foundation
import SwiftUI
import Combine

/// Navigation destinations (sidebar primary nav).
enum AppSection: String, CaseIterable, Identifiable {
    case chat = "Chat"
    case knowledge = "Knowledge Base"
    case modelZoo = "Model Zoo"
    case indexing = "Indexing"
    case diagnostics = "Diagnostics"
    case settings = "Settings"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .chat: return "bubble.left.and.text.bubble.right"
        case .knowledge: return "books.vertical"
        case .modelZoo: return "cpu"
        case .indexing: return "square.stack.3d.up"
        case .diagnostics: return "stethoscope"
        case .settings: return "gearshape"
        }
    }
}

/// Composition root — owns every service/store and wires their dependencies.
/// Injected once at the top of the view tree.
@MainActor
final class AppEnvironment: ObservableObject {
    let settingsStore: SettingsStore
    let inference: InferenceManager
    let telemetry: TelemetryService
    let indexing: IndexingService
    let projects: ProjectStore
    let chat: ChatViewModel
    let ollamaControl: OllamaControlService
    let database: AppDatabase
    let theme = ThemeManager.shared

    @Published var section: AppSection = .chat
    @Published var inspectorVisible = true

    init() {
        let settings = SettingsStore()
        let inference = InferenceManager(settingsStore: settings)
        let telemetry = TelemetryService()

        let dbURL = settings.databaseURL
        let database = (try? AppDatabase(path: dbURL)) ?? AppDatabase.inMemoryFallback()
        let indexing = IndexingService(database: database, settingsStore: settings, inference: inference)
        let projects = ProjectStore(settingsStore: settings)
        projects.indexingService = indexing

        let chat = ChatViewModel(settingsStore: settings, inference: inference,
                                 indexing: indexing, projects: projects)

        let ollamaControl = OllamaControlService(settingsStore: settings)

        self.settingsStore = settings
        self.inference = inference
        self.telemetry = telemetry
        self.indexing = indexing
        self.projects = projects
        self.chat = chat
        self.ollamaControl = ollamaControl
        self.database = database

        // Global model-state wiring: discovery falls back to the on-disk `ollama
        // list` catalog while the server is offline, and any CLI action (pull /
        // load / unload / server start-stop) triggers an immediate re-discovery so
        // Model Zoo, Auto-Configure, Settings and the sidebar all update together.
        inference.offlineCatalog = { [weak ollamaControl] in
            await ollamaControl?.installedCatalog() ?? []
        }
        ollamaControl.onCatalogChanged = { [weak inference] in
            Task { await inference?.refresh() }
        }

        // Debug/testing affordance: `open "Aura Local.app" --args -startSection "Model Zoo"`
        if let s = UserDefaults.standard.string(forKey: "startSection"),
           let sec = AppSection(rawValue: s) {
            section = sec
        }
    }

    // MARK: - Reset / cleanup

    /// Wipe the vector store, chat history, and vault registrations — but keep the
    /// user's settings and theme. Removes the on-disk state files so nothing reloads.
    func clearIndexAndChats() {
        indexing.cancel()
        database.wipeAll()
        indexing.clearVectorIndexes()
        projects.removeAllProjects()
        indexing.indexedFiles = [:]
        chat.sessions = []
        chat.newSession()
        try? FileManager.default.removeItem(at: AppPaths.sessionsFile)
        try? FileManager.default.removeItem(at: AppPaths.projectsFile)
    }

    /// Full factory reset — the above plus erasing settings/theme back to defaults.
    func factoryReset() {
        clearIndexAndChats()
        for url in AppPaths.allDataFiles { try? FileManager.default.removeItem(at: url) }
        settingsStore.settings = AppSettings()   // debounced save re-seeds defaults
    }

    func onLaunch() {
        telemetry.start()
        inference.startPolling()
        // Show the persisted index state — no re-scan, no re-embed. Loaded off-main so
        // a large vault (32k+ files) doesn't stall launch. Offline edits reconcile on
        // the next (incremental) Scan or live save.
        indexing.rebuildInventoryAsync(projects: projects.projects)
        Task {
            await ollamaControl.refreshRunning()
            await ollamaControl.refreshInstalled()
        }
    }

    func onQuit() {
        telemetry.stop()
        inference.stopPolling()
        projects.stopAll()
    }
}

extension AppDatabase {
    /// Last-resort in-memory store so the UI still runs if the on-disk DB fails.
    static func inMemoryFallback() -> AppDatabase {
        // try the temp dir; if even that fails we crash loudly which is correct.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("aura_fallback.sqlite")
        return try! AppDatabase(path: tmp)
    }
}
