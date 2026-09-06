//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import Foundation

/// Normalized result of reading any supported document. Every format is converted
/// to **Markdown** so the single heading-aware `MarkdownChunker` handles chunking
/// uniformly (headings become breadcrumbs; code/tables stay intact). `warnings`
/// surface non-fatal issues (truncation, empty PDF pages, partial parses) to the
/// diagnostics / per-file Issues UI without failing the index.
struct ExtractedDocument {
    var markdown: String
    var title: String? = nil
    var tags: [String] = []
    var aliases: [String] = []
    var links: [String] = []
    var warnings: [String] = []

    var isEmpty: Bool { markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Format-dispatching reader. Each category delegates to a focused extractor; all
/// of them are defensive — a malformed file yields a best-effort result plus a
/// warning, never a throw into the indexing loop.
enum DocumentExtractor {

    static func extract(_ file: ScannedFile, settings: AppSettings) -> ExtractedDocument? {
        let category = SupportedFormats.category(for: file.ext) ?? .plain
        let fallbackTitle = (file.fileName as NSString).deletingPathExtension

        do {
            switch category {
            case .markdown:
                guard let raw = readUTF8(file) else { return nil }
                let note = ObsidianParser.parse(raw)
                return ExtractedDocument(markdown: note.cleanedBody,
                                         title: note.aliases.first ?? fallbackTitle,
                                         tags: note.tags, aliases: note.aliases, links: note.wikilinks)
            case .plain:
                guard let raw = readUTF8(file) else { return nil }
                return ExtractedDocument(markdown: raw, title: fallbackTitle)
            case .code:
                guard let raw = readUTF8(file) else { return nil }
                // Wrap in a fence so the markdown chunker won't treat code lines that
                // start with '#' as headings, and won't split mid-listing.
                return ExtractedDocument(markdown: "```\(file.ext)\n\(raw)\n```", title: fallbackTitle)
            case .web:      return try HTMLExtractor.extract(file, fallbackTitle: fallbackTitle)
            case .office:   return try DocxExtractor.extract(file, fallbackTitle: fallbackTitle)
            case .ebook:    return try EpubExtractor.extract(file, fallbackTitle: fallbackTitle)
            case .richText: return try RichTextExtractor.extract(file, fallbackTitle: fallbackTitle)
            case .tabular:  return try TabularExtractor.extract(file, fallbackTitle: fallbackTitle)
            case .wiki:     return try WikiExtractor.extract(file, fallbackTitle: fallbackTitle)
            case .pdf:      return PDFExtractor.extract(file, fallbackTitle: fallbackTitle,
                                                        ocrFallback: settings.pdfOCRFallback)
            }
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            Log.ingest.warning("Structured parse failed for \(file.relativePath): \(reason)")
            // Last-ditch: index as plain text so the file still contributes keyword recall.
            if let raw = readUTF8(file), !raw.isEmpty {
                return ExtractedDocument(markdown: raw, title: fallbackTitle,
                                         warnings: ["Structured parse failed; indexed as plain text (\(reason))."])
            }
            return nil
        }
    }

    /// Robust text read: UTF-8, then Latin-1 as a fallback for legacy encodings.
    static func readUTF8(_ file: ScannedFile) -> String? {
        if let s = try? String(contentsOf: file.url, encoding: .utf8) { return s }
        if let data = try? Data(contentsOf: file.url) {
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        }
        return nil
    }
}
