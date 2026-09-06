//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import Foundation

/// Creates and resolves security-scoped bookmarks so the app keeps read/write
/// access to user-selected folders (Obsidian / Markdown vaults) across launches.
///
/// On a non-sandboxed build these bookmarks still resolve correctly; the
/// `.withSecurityScope` option is honored under the App Sandbox when present.
enum BookmarkStore {

    /// Create read/write bookmark data for a user-selected URL.
    static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Resolve a stored bookmark back into a URL, refreshing it if stale.
    /// Returns the URL and (possibly) refreshed bookmark data.
    static func resolve(_ data: Data) throws -> (url: URL, refreshed: Data?) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if isStale {
            let fresh = try? makeBookmark(for: url)
            return (url, fresh)
        }
        return (url, nil)
    }

    /// Run a block with security-scoped access started, ensuring it is stopped.
    @discardableResult
    static func withAccess<T>(_ data: Data, _ body: (URL) throws -> T) throws -> T {
        let (url, _) = try resolve(data)
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }
}
