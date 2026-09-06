//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import Foundation

/// Single source of truth for the app's identity at runtime.
///
/// The version is read from the bundle's `Info.plist` (`CFBundleShortVersionString`)
/// — the same value the release script bumps and Sparkle advertises. **Never hardcode
/// the version in the UI**: derive it from here so it can't go stale on the next
/// release (that's exactly how the About footer shipped a wrong number once).
enum AppInfo {
    static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
    }
    static var build: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? version
    }
    /// Display form, e.g. `v3.3.2`.
    static var versionDisplay: String { "v\(version)" }

    /// The bundled release notes (`CHANGELOG.md`, copied into the app's `Resources`
    /// by `Packaging/build_app.sh`). `nil` for a bare `swift run` where it isn't
    /// bundled — callers fall back gracefully.
    static var changelogMarkdown: String? {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text
    }

    /// The changelog section for a specific version — `## [x.y.z] …` up to (but not
    /// including) the next `## ` heading — so "What's New" can lead with the current
    /// release's notes rather than the whole history.
    static func releaseNotes(for version: String) -> String? {
        guard let full = changelogMarkdown else { return nil }
        return section(of: full, version: version)
    }

    /// Extract a single version's section from a Keep-a-Changelog document.
    static func section(of changelog: String, version: String) -> String? {
        var out: [String] = []
        var capturing = false
        for line in changelog.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                if capturing { break }                       // reached the next version
                // Match `## [3.3.2]` (and tolerate `## 3.3.2`).
                capturing = line.contains("[\(version)]") || line.contains("] \(version)")
                    || line.dropFirst(3).trimmingCharacters(in: .whitespaces).hasPrefix(version)
            }
            if capturing { out.append(line) }
        }
        let joined = out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }
}
