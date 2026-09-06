//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import Foundation

/// Parsed representation of an Obsidian / Markdown note.
struct ParsedNote {
    var frontmatter: [String: [String]] = [:]   // raw key -> values (lists flattened)
    var tags: [String] = []
    var aliases: [String] = []
    var wikilinks: [String] = []                  // resolved targets (without alias/heading)
    var embeds: [String] = []                     // ![[...]] targets
    var cleanedBody: String = ""                  // body with links flattened to readable text
}

/// Custom ingestion engine tailored for Obsidian syntax:
///  - YAML frontmatter extraction (tags, aliases, custom props)
///  - wikilink + embed resolution, flattening links to readable text for the LLM
///    while preserving the relational metadata.
enum ObsidianParser {

    static func parse(_ raw: String) -> ParsedNote {
        var note = ParsedNote()
        var body = raw

        // 1. Frontmatter (--- ... --- at the very top)
        if let fm = extractFrontmatter(raw) {
            note.frontmatter = fm.map
            note.tags = fm.tags
            note.aliases = fm.aliases
            body = fm.remainingBody
        }

        // 2. Inline #tags (outside code spans, simple heuristic)
        note.tags += inlineTags(in: body)
        note.tags = Array(Set(note.tags)).sorted()

        // 3. Embeds  ![[target]]   (capture before wikilinks so the ! isn't lost)
        let embedRegex = try? NSRegularExpression(pattern: "!\\[\\[([^\\]]+)\\]\\]")
        body = replace(body, regex: embedRegex) { inner in
            let target = inner.split(separator: "|").first.map(String.init) ?? inner
            let clean = target.split(separator: "#").first.map(String.init) ?? target
            note.embeds.append(clean.trimmingCharacters(in: .whitespaces))
            return ""   // drop embedded media/notes from LLM context
        }

        // 4. Wikilinks  [[target]] or [[target|alias]] or [[target#heading]]
        let linkRegex = try? NSRegularExpression(pattern: "\\[\\[([^\\]]+)\\]\\]")
        body = replace(body, regex: linkRegex) { inner in
            let parts = inner.split(separator: "|", maxSplits: 1).map(String.init)
            let targetRaw = parts[0]
            let display = parts.count > 1 ? parts[1] : (targetRaw.split(separator: "#").first.map(String.init) ?? targetRaw)
            let target = targetRaw.split(separator: "#").first.map(String.init) ?? targetRaw
            note.wikilinks.append(target.trimmingCharacters(in: .whitespaces))
            return display   // keep readable label in body
        }

        note.wikilinks = Array(Set(note.wikilinks)).sorted()
        note.cleanedBody = body
        return note
    }

    // MARK: - Frontmatter

    private struct Frontmatter {
        var map: [String: [String]]
        var tags: [String]
        var aliases: [String]
        var remainingBody: String
    }

    private static func extractFrontmatter(_ raw: String) -> Frontmatter? {
        let trimmed = raw.hasPrefix("\u{FEFF}") ? String(raw.dropFirst()) : raw
        guard trimmed.hasPrefix("---") else { return nil }
        let lines = trimmed.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        var endIndex: Int?
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" { endIndex = i; break }
        }
        guard let end = endIndex else { return nil }

        var map: [String: [String]] = [:]
        var currentKey: String?
        for i in 1..<end {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            // list item belonging to previous key:  "  - value"
            if let key = currentKey, line.first == " " || line.first == "\t" || line.trimmingCharacters(in: .whitespaces).hasPrefix("-") {
                let item = line.trimmingCharacters(in: .whitespaces)
                if item.hasPrefix("-") {
                    let v = cleanScalar(String(item.dropFirst()))
                    if !v.isEmpty { map[key, default: []].append(v) }
                    continue
                }
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let valuePart = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            currentKey = key
            if valuePart.isEmpty {
                map[key] = map[key] ?? []
            } else if valuePart.hasPrefix("[") {
                // inline list: [a, b, c]
                let inner = valuePart.dropFirst().dropLast(valuePart.hasSuffix("]") ? 1 : 0)
                let items = inner.split(separator: ",").map { cleanScalar(String($0)) }.filter { !$0.isEmpty }
                map[key] = items
            } else {
                map[key] = [cleanScalar(valuePart)]
            }
        }

        let tags = (map["tags"] ?? []) + (map["tag"] ?? [])
        let aliases = (map["aliases"] ?? []) + (map["alias"] ?? [])

        let remaining = lines[(end + 1)...].joined(separator: "\n")
        return Frontmatter(map: map, tags: tags, aliases: aliases, remainingBody: remaining)
    }

    private static func cleanScalar(_ s: String) -> String {
        var v = s.trimmingCharacters(in: .whitespaces)
        if (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")), v.count >= 2 {
            v = String(v.dropFirst().dropLast())
        }
        if v.hasPrefix("#") { v = String(v.dropFirst()) }
        return v.trimmingCharacters(in: .whitespaces)
    }

    private static func inlineTags(in body: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "(?:^|\\s)#([A-Za-z0-9_][\\w/-]*)") else { return [] }
        let ns = body as NSString
        let matches = regex.matches(in: body, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { m in
            guard m.numberOfRanges > 1 else { return nil }
            return ns.substring(with: m.range(at: 1))
        }
    }

    // MARK: - regex replace helper

    private static func replace(_ input: String, regex: NSRegularExpression?, _ transform: (String) -> String) -> String {
        guard let regex else { return input }
        let ns = input as NSString
        var result = ""
        var last = 0
        for m in regex.matches(in: input, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let inner = m.numberOfRanges > 1 ? ns.substring(with: m.range(at: 1)) : ""
            result += transform(inner)
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}
