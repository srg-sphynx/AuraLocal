//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import Foundation

/// HTML / HTM / XHTML → Markdown.
enum HTMLExtractor {
    static func extract(_ file: ScannedFile, fallbackTitle: String) throws -> ExtractedDocument {
        guard let html = DocumentExtractor.readUTF8(file) else {
            throw AuraError.fileUnreadable(path: file.relativePath)
        }
        let (md, title) = try HTMLToMarkdown.convert(html)
        var warnings: [String] = []
        if md.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append("No readable text after stripping HTML boilerplate.")
        }
        return ExtractedDocument(markdown: md, title: title ?? fallbackTitle, warnings: warnings)
    }
}
