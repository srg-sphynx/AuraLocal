//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import Foundation
import PDFKit

struct ScannedFile {
    var url: URL
    var relativePath: String
    var fileName: String
    var ext: String
    var byteSize: Int64
    var modifiedAt: Date
}

/// Reads supported documents and enumerates vault directories while honoring
/// the indexing rules (included extensions + excluded glob patterns). The
/// hidden `.obsidian` config folder, plugin dirs and media assets are skipped.
enum FileIngestor {

    static let alwaysExcludedDirs: Set<String> = [".obsidian", ".trash", ".git", ".github", "node_modules", ".obsidian.vimrc"]

    static func scan(root: URL, settings: AppSettings) -> [ScannedFile] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                             options: [.skipsHiddenFiles], errorHandler: nil) else { return [] }
        var results: [ScannedFile] = []
        let included = Set(settings.includedExtensions.map { $0.lowercased() })

        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            // Skip excluded directories early (don't descend).
            if alwaysExcludedDirs.contains(name) {
                enumerator.skipDescendants(); continue
            }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if isExcludedDir(name, settings: settings) { enumerator.skipDescendants() }
                continue
            }
            guard values?.isRegularFile == true else { continue }
            let ext = url.pathExtension.lowercased()
            guard included.contains(ext) else { continue }

            let rel = relativePath(of: url, root: root)
            if isExcluded(path: rel, name: name, settings: settings) { continue }

            results.append(ScannedFile(
                url: url,
                relativePath: rel,
                fileName: name,
                ext: ext,
                byteSize: Int64(values?.fileSize ?? 0),
                modifiedAt: values?.contentModificationDate ?? .distantPast
            ))
        }
        return results
    }

    static func relativePath(of url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        if filePath.hasPrefix(rootPath) {
            return String(filePath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return url.lastPathComponent
    }

    static func isExcludedDir(_ name: String, settings: AppSettings) -> Bool {
        if alwaysExcludedDirs.contains(name) { return true }
        return settings.excludedPatterns.contains { pattern in
            !pattern.contains("*") && pattern == name
        }
    }

    static func isExcluded(path: String, name: String, settings: AppSettings) -> Bool {
        for pattern in settings.excludedPatterns {
            if pattern.hasPrefix("*.") {
                let ext = pattern.dropFirst(1) // ".png"
                if name.lowercased().hasSuffix(ext.lowercased()) { return true }
            } else if pattern.contains("*") {
                if fnmatch(pattern, path, 0) == 0 { return true }
            } else {
                // bare token — match any path component
                if path.split(separator: "/").contains(Substring(pattern)) || name == pattern { return true }
            }
        }
        return false
    }

    /// Read text content for a supported file. PDFs are extracted page-by-page.
    static func readText(_ file: ScannedFile) -> String? {
        switch file.ext {
        case "pdf":
            guard let doc = PDFDocument(url: file.url) else { return nil }
            var out = ""
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i), let s = page.string {
                    out += s + "\n\n"
                }
            }
            return out.isEmpty ? nil : out
        default:
            if let s = try? String(contentsOf: file.url, encoding: .utf8) { return s }
            if let data = try? Data(contentsOf: file.url) {
                return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
            }
            return nil
        }
    }
}
