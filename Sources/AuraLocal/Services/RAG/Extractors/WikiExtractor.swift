import Foundation

/// Wiki markup → Markdown. Handles the common cases:
///  - `.html` exports (Confluence/DokuWiki/etc.) → routed to the HTML converter.
///  - MediaWiki markup (`.wiki` / `.mediawiki`) → a lightweight converter for
///    headings, bold/italic, internal/external links, lists, tables and templates.
/// Markdown-flavored wiki exports (`.md`) never reach here — they map to the
/// markdown category and go through `ObsidianParser`.
enum WikiExtractor {
    static func extract(_ file: ScannedFile, fallbackTitle: String) throws -> ExtractedDocument {
        guard let raw = DocumentExtractor.readUTF8(file) else {
            throw AuraError.fileUnreadable(path: file.relativePath)
        }
        // Defensive: some wiki dumps are actually HTML.
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("<!doctype html") || trimmed.hasPrefix("<html") {
            let (md, title) = try HTMLToMarkdown.convert(raw)
            return ExtractedDocument(markdown: md, title: title ?? fallbackTitle)
        }

        var links: [String] = []
        var tags: [String] = []
        let md = convertMediaWiki(raw, links: &links, tags: &tags)
        return ExtractedDocument(markdown: md, title: fallbackTitle,
                                 tags: Array(Set(tags)).sorted(),
                                 links: Array(Set(links)).sorted())
    }

    // MARK: - MediaWiki → Markdown

    static func convertMediaWiki(_ input: String, links: inout [String], tags: inout [String]) -> String {
        var text = input

        // Strip HTML-ish citation/comment noise.
        text = regexReplace(text, #"<ref[^>]*>.*?</ref>"#, "", options: [.dotMatchesLineSeparators])
        text = regexReplace(text, #"<ref[^>]*/>"#, "")
        text = regexReplace(text, #"<!--.*?-->"#, "", options: [.dotMatchesLineSeparators])

        // Categories → tags, then removed from the body.
        for m in matches(text, #"\[\[Category:([^\]|]+)(?:\|[^\]]*)?\]\]"#) { tags.append(m.trimmingCharacters(in: .whitespaces)) }
        text = regexReplace(text, #"\[\[Category:[^\]]+\]\]"#, "")
        // Drop File/Image embeds.
        text = regexReplace(text, #"\[\[(?:File|Image):[^\]]+\]\]"#, "")

        // Internal links [[Target|Label]] / [[Target]] → readable label, capture target.
        for t in matches(text, #"\[\[([^\]|#]+)(?:[#|][^\]]*)?\]\]"#) { links.append(t.trimmingCharacters(in: .whitespaces)) }
        text = regexReplace(text, #"\[\[([^\]|]+)\|([^\]]+)\]\]"#, "$2")
        text = regexReplace(text, #"\[\[([^\]]+)\]\]"#, "$1")

        // External links [http://url Label] → Label ; [http://url] → url
        text = regexReplace(text, #"\[(?:https?://|//)[^\s\]]+\s+([^\]]+)\]"#, "$1")
        text = regexReplace(text, #"\[((?:https?://|//)[^\s\]]+)\]"#, "$1")

        // Bold/italic: '''bold''' , ''italic''  (bold first to avoid clobbering).
        text = regexReplace(text, #"'''(.+?)'''"#, "**$1**")
        text = regexReplace(text, #"''(.+?)''"#, "*$1*")

        // Templates {{...}} (may nest one level) → removed.
        text = regexReplace(text, #"\{\{[^{}]*\}\}"#, "")
        text = regexReplace(text, #"\{\{[^{}]*\}\}"#, "")

        // Line-oriented: headings, lists, tables.
        var out: [String] = []
        var inTable = false
        var tableRows: [[String]] = []
        var currentRow: [String] = []

        func flushTable() {
            guard !tableRows.isEmpty else { inTable = false; return }
            let cols = tableRows.map(\.count).max() ?? 0
            func pad(_ r: [String]) -> [String] { r + Array(repeating: "", count: max(0, cols - r.count)) }
            out.append("")
            out.append("| " + pad(tableRows[0]).joined(separator: " | ") + " |")
            out.append("| " + Array(repeating: "---", count: cols).joined(separator: " | ") + " |")
            for r in tableRows.dropFirst() { out.append("| " + pad(r).joined(separator: " | ") + " |") }
            out.append("")
            tableRows = []; currentRow = []; inTable = false
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine

            if line.hasPrefix("{|") { inTable = true; tableRows = []; currentRow = []; continue }
            if inTable {
                if line.hasPrefix("|}") { if !currentRow.isEmpty { tableRows.append(currentRow) }; flushTable(); continue }
                if line.hasPrefix("|-") { if !currentRow.isEmpty { tableRows.append(currentRow); currentRow = [] }; continue }
                if line.hasPrefix("!") || line.hasPrefix("|") {
                    let body = String(line.dropFirst())
                    // cells can be separated by "||"
                    for cell in body.components(separatedBy: "||") {
                        let clean = cell.replacingOccurrences(of: "|", with: "\\|").trimmingCharacters(in: .whitespaces)
                        currentRow.append(clean)
                    }
                }
                continue
            }

            // Headings: = H1 =, == H2 ==, ...
            if let h = headingLine(line) {
                out.append(""); out.append(String(repeating: "#", count: h.level) + " " + h.title); out.append("")
                continue
            }
            // Lists: leading * or #  (wiki '#' = ordered list, not heading)
            let stars = line.prefix(while: { $0 == "*" }).count
            let hashes = line.prefix(while: { $0 == "#" }).count
            if stars > 0 {
                let content = line.dropFirst(stars).trimmingCharacters(in: .whitespaces)
                out.append(String(repeating: "  ", count: stars - 1) + "- " + content); continue
            }
            if hashes > 0 {
                let content = line.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
                out.append(String(repeating: "  ", count: hashes - 1) + "1. " + content); continue
            }
            if line.hasPrefix(";") { out.append("**" + line.dropFirst().trimmingCharacters(in: .whitespaces) + "**"); continue }
            if line.hasPrefix(":") { out.append("> " + line.dropFirst().trimmingCharacters(in: .whitespaces)); continue }
            if line.hasPrefix("----") { out.append("\n---\n"); continue }

            out.append(line)
        }
        if inTable { flushTable() }

        let joined = out.joined(separator: "\n")
        return joined.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
                     .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func headingLine(_ line: String) -> (level: Int, title: String)? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("=") && t.hasSuffix("=") && t.count >= 3 else { return nil }
        let leading = t.prefix(while: { $0 == "=" }).count
        let trailing = t.reversed().prefix(while: { $0 == "=" }).count
        let level = min(6, min(leading, trailing))
        guard level >= 1 else { return nil }
        let title = String(t.dropFirst(level).dropLast(level)).trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return (level, title)
    }

    // MARK: - regex helpers

    private static func regexReplace(_ s: String, _ pattern: String, _ template: String,
                                     options: NSRegularExpression.Options = []) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return re.stringByReplacingMatches(in: s, range: range, withTemplate: template)
    }

    private static func matches(_ s: String, _ pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).compactMap {
            $0.numberOfRanges > 1 ? ns.substring(with: $0.range(at: 1)) : nil
        }
    }
}
