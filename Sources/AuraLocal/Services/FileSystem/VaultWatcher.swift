//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import Foundation

/// Watches a vault directory using NSFileCoordinator + NSFilePresenter so edits
/// made *inside Obsidian* are detected and the affected note re-indexed in the
/// background. Subitem changes are debounced and reported as relative paths.
final class VaultWatcher: NSObject, NSFilePresenter {

    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue
    private let rootURL: URL
    private let onChange: (String) -> Void          // relative path
    private var debounce: [String: DispatchWorkItem] = [:]
    private let lock = NSLock()

    init(rootURL: URL, onChange: @escaping (String) -> Void) {
        self.rootURL = rootURL.standardizedFileURL
        self.presentedItemURL = rootURL.standardizedFileURL
        self.onChange = onChange
        let q = OperationQueue()
        q.name = "com.aura.local.vaultwatcher"
        q.maxConcurrentOperationCount = 1
        self.presentedItemOperationQueue = q
        super.init()
    }

    func start() { NSFileCoordinator.addFilePresenter(self) }
    func stop() {
        NSFileCoordinator.removeFilePresenter(self)
        lock.lock(); debounce.values.forEach { $0.cancel() }; debounce.removeAll(); lock.unlock()
    }

    // A descendant of the vault changed (created / modified / removed / renamed).
    func presentedSubitemDidChange(at url: URL) {
        let rel = relativePath(of: url)
        guard !rel.isEmpty, !isIgnored(rel) else { return }
        schedule(rel)
    }

    func presentedItemDidChange() { /* directory-level change; ignored */ }

    // MARK: - helpers

    private func schedule(_ rel: String) {
        lock.lock(); defer { lock.unlock() }
        debounce[rel]?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange(rel) }
        debounce[rel] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func relativePath(of url: URL) -> String {
        let root = rootURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(root) else { return "" }
        return String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func isIgnored(_ rel: String) -> Bool {
        let components = rel.split(separator: "/").map(String.init)
        if components.contains(where: { FileIngestor.alwaysExcludedDirs.contains($0) }) { return true }
        let ext = (rel as NSString).pathExtension.lowercased()
        // Ignore changes to unsupported assets and temp/swap files.
        if !SupportedFormats.isSupported(ext) { return true }
        if rel.hasSuffix("~") || rel.contains(".tmp") { return true }
        return false
    }
}
