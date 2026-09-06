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
import Sparkle

/// Thin wrapper around Sparkle's standard updater so SwiftUI can drive it.
///
/// The updater reads its configuration from `Info.plist`:
///   • `SUFeedURL`     — the appcast URL to poll for new versions.
///   • `SUPublicEDKey` — the EdDSA public key used to verify downloaded archives.
///   • `SUEnableAutomaticChecks` — whether to check in the background.
///
/// See `docs/UPDATES.md` for how to generate keys, sign a build, and publish.
@MainActor
final class UpdaterService: ObservableObject {
    private let controller: SPUStandardUpdaterController

    /// Mirrors `SPUUpdater.canCheckForUpdates` so menu items / buttons can disable
    /// themselves while a check is already in flight.
    @Published var canCheckForUpdates = false

    init() {
        // `startingUpdater: true` boots the background scheduler immediately and
        // wires up the standard user-facing update UI (the "A new version is
        // available" window, progress, install-and-relaunch).
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// User-initiated check — always shows UI, even when already up to date.
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    /// Background auto-check preference, surfaced in Settings.
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Human-readable feed target, for display/diagnostics. Read straight from the
    /// bundle so it reflects the shipped `SUFeedURL` without touching Sparkle's
    /// deprecated `feedURL` accessor.
    var feedURLString: String {
        (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String) ?? "(not configured)"
    }
}
