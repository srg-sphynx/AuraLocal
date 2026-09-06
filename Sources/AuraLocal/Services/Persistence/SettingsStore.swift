//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import Foundation
import Combine

/// Observable wrapper around `AppSettings` with JSON persistence + debounced save.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { scheduleSave() }
    }

    private var saveTask: Task<Void, Never>?

    init() {
        if let data = try? Data(contentsOf: AppPaths.settingsFile),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = Self.migrate(decoded)
        } else {
            self.settings = AppSettings()
        }
    }

    /// One-time upgrades applied to a decoded settings blob. Currently: merge the
    /// formats added in v3 (HTML/DOCX/EPUB/wiki/…) into the user's existing
    /// `includedExtensions` so upgrading picks them up without losing prior choices.
    private static func migrate(_ decoded: AppSettings) -> AppSettings {
        var s = decoded
        if !s.formatsUpgradedV3 {
            let merged = Set(s.includedExtensions.map { $0.lowercased() })
                .union(SupportedFormats.defaultIncludedExtensions)
            s.includedExtensions = merged.sorted()
            s.formatsUpgradedV3 = true
        }
        return s
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = settings
        saveTask = Task { [snapshot] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: AppPaths.settingsFile, options: .atomic)
            }
        }
    }

    var databaseURL: URL {
        if settings.vectorStorePath.isEmpty {
            return AppPaths.defaultDatabaseFile
        }
        return URL(fileURLWithPath: settings.vectorStorePath)
    }
}
