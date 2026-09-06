//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import Foundation
import AppKit

/// RTF / RTFD → plain text via AppKit's native reader (auto-detects the document
/// type from the URL, and handles the RTFD bundle directory transparently).
enum RichTextExtractor {
    static func extract(_ file: ScannedFile, fallbackTitle: String) throws -> ExtractedDocument {
        do {
            let attr = try NSAttributedString(url: file.url, options: [:], documentAttributes: nil)
            let text = attr.string
            var warnings: [String] = []
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                warnings.append("Rich-text document contained no extractable text.")
            }
            return ExtractedDocument(markdown: text, title: fallbackTitle, warnings: warnings)
        } catch {
            throw AuraError.parseFailed(path: file.relativePath, reason: error.localizedDescription)
        }
    }
}
