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
