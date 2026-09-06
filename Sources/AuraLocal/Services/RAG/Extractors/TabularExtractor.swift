//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import Foundation

/// CSV / TSV → a Markdown table so tabular data stays retrievable (header row +
/// rows). Oversized sheets are capped with a warning to keep chunks sane.
enum TabularExtractor {
    private static let maxRows = 500
    private static let maxCols = 24

    static func extract(_ file: ScannedFile, fallbackTitle: String) throws -> ExtractedDocument {
        guard let raw = DocumentExtractor.readUTF8(file) else {
            throw AuraError.fileUnreadable(path: file.relativePath)
        }
        let delimiter: Character = (file.ext == "tsv") ? "\t" : ","
        var rows = parse(raw, delimiter: delimiter)
        var warnings: [String] = []

        guard !rows.isEmpty else {
            return ExtractedDocument(markdown: "", title: fallbackTitle,
                                     warnings: ["Empty table."])
        }
        if rows.count > maxRows {
            warnings.append("Table truncated to first \(maxRows) of \(rows.count) rows.")
            rows = Array(rows.prefix(maxRows))
        }
        let colCount = rows.map(\.count).max() ?? 0
        if colCount > maxCols {
            warnings.append("Table truncated to first \(maxCols) of \(colCount) columns.")
            rows = rows.map { Array($0.prefix(maxCols)) }
        }
        return ExtractedDocument(markdown: toMarkdownTable(rows), title: fallbackTitle, warnings: warnings)
    }

    /// Quote-aware CSV/TSV parse: handles quoted fields containing the delimiter,
    /// newlines, and escaped quotes ("").
    static func parse(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        func endField() { row.append(field); field = "" }
        func endRow() { endField(); if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }; row = [] }

        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { inQuotes = false }
                } else { field.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case delimiter: endField()
                case "\r": break
                case "\n": endRow()
                default: field.append(c)
                }
            }
            i += 1
        }
        // trailing field / row
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    private static func toMarkdownTable(_ rows: [[String]]) -> String {
        guard let header = rows.first else { return "" }
        let cols = rows.map(\.count).max() ?? header.count
        func pad(_ r: [String]) -> [String] {
            r.map { $0.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") }
             + Array(repeating: "", count: max(0, cols - r.count))
        }
        var md = "| " + pad(header).joined(separator: " | ") + " |\n"
        md += "| " + Array(repeating: "---", count: cols).joined(separator: " | ") + " |\n"
        for r in rows.dropFirst() { md += "| " + pad(r).joined(separator: " | ") + " |\n" }
        return md
    }
}
