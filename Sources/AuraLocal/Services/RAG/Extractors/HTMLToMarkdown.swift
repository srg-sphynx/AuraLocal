import Foundation
import SwiftSoup

/// Converts HTML/XHTML into clean Markdown that preserves structure the RAG chunker
/// cares about: headings (→ breadcrumbs), lists, code, blockquotes and tables.
/// Boilerplate (script/style/nav/footer/aside) is stripped so it never pollutes
/// embeddings. Links are flattened to their readable label (the href is dropped —
/// the LLM can't follow it anyway).
enum HTMLToMarkdown {

    /// Returns normalized Markdown plus the document `<title>` when present.
    static func convert(_ html: String) throws -> (markdown: String, title: String?) {
        let doc = try SwiftSoup.parse(html)
        let rawTitle = (try? doc.title())?.trimmingCharacters(in: .whitespacesAndNewlines)
        try doc.select("script, style, noscript, nav, footer, aside, form, svg, iframe, header").remove()

        let root: Element = doc.body() ?? doc
        var out = ""
        try renderChildren(root, into: &out)
        let md = collapseBlankLines(out)
        return (md, (rawTitle?.isEmpty == false) ? rawTitle : nil)
    }

    // MARK: - Block rendering

    private static func renderChildren(_ el: Element, into out: inout String) throws {
        for node in el.getChildNodes() { try render(node, into: &out) }
    }

    private static func render(_ node: Node, into out: inout String) throws {
        if let t = node as? TextNode { out += t.text(); return }
        guard let el = node as? Element else { return }

        switch el.tagName().lowercased() {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(String(el.tagName().dropFirst())) ?? 1
            let text = try inlineText(el)
            if !text.isEmpty { out += "\n\n" + String(repeating: "#", count: level) + " " + text + "\n\n" }
        case "p", "div", "section", "article", "main":
            out += "\n\n"; try renderChildren(el, into: &out); out += "\n\n"
        case "br":
            out += "\n"
        case "hr":
            out += "\n\n---\n\n"
        case "pre":
            let text = try el.text()
            if !text.isEmpty { out += "\n\n```\n\(text)\n```\n\n" }
        case "blockquote":
            var inner = ""; try renderChildren(el, into: &inner)
            let quoted = inner.split(separator: "\n").map { "> \($0)" }.joined(separator: "\n")
            if !quoted.isEmpty { out += "\n\n" + quoted + "\n\n" }
        case "ul", "ol":
            out += "\n" + (try renderList(el)) + "\n"
        case "table":
            let t = try renderTable(el)
            if !t.isEmpty { out += "\n\n" + t + "\n\n" }
        case "strong", "b", "em", "i", "code", "a", "span", "small", "mark", "sup", "sub":
            out += try inline(el)
        case "img":
            let alt = (try? el.attr("alt")) ?? ""
            if !alt.isEmpty { out += "[image: \(alt)]" }
        default:
            try renderChildren(el, into: &out)
        }
    }

    private static func renderList(_ el: Element, depth: Int = 0) throws -> String {
        let ordered = el.tagName().lowercased() == "ol"
        var lines: [String] = []
        var i = 1
        let indent = String(repeating: "  ", count: depth)
        for li in el.children().array() where li.tagName().lowercased() == "li" {
            let text = try inlineText(li)
            let marker = ordered ? "\(i). " : "- "
            lines.append(indent + marker + text)
            // nested lists
            for child in li.children().array() where ["ul", "ol"].contains(child.tagName().lowercased()) {
                lines.append(try renderList(child, depth: depth + 1))
            }
            i += 1
        }
        return lines.joined(separator: "\n")
    }

    private static func renderTable(_ table: Element) throws -> String {
        var rows: [[String]] = []
        for tr in try table.select("tr").array() {
            var cells: [String] = []
            for cell in try tr.select("th, td").array() {
                cells.append(try inlineText(cell).replacingOccurrences(of: "|", with: "\\|"))
            }
            if !cells.isEmpty { rows.append(cells) }
        }
        guard let first = rows.first else { return "" }
        let cols = rows.map(\.count).max() ?? first.count
        func pad(_ r: [String]) -> [String] { r + Array(repeating: "", count: max(0, cols - r.count)) }
        var md = "| " + pad(first).joined(separator: " | ") + " |\n"
        md += "| " + Array(repeating: "---", count: cols).joined(separator: " | ") + " |\n"
        for r in rows.dropFirst() { md += "| " + pad(r).joined(separator: " | ") + " |\n" }
        return md
    }

    // MARK: - Inline rendering

    /// Render an element's inline content (recursively) and collapse whitespace.
    private static func inlineText(_ el: Element) throws -> String {
        var s = ""
        for node in el.getChildNodes() {
            if let t = node as? TextNode { s += t.text() }
            else if let e = node as? Element { s += try inline(e) }
        }
        return s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Block-level tags that must not be flattened into a parent's inline text — they
    /// are emitted separately by the block renderer (avoids nested-list duplication).
    private static let blockTags: Set<String> = ["ul", "ol", "table", "pre", "blockquote", "figure"]

    private static func inline(_ el: Element) throws -> String {
        let tag = el.tagName().lowercased()
        if blockTags.contains(tag) { return "" }
        let inner = try inlineText(el)
        switch tag {
        case "strong", "b": return inner.isEmpty ? "" : "**\(inner)**"
        case "em", "i":     return inner.isEmpty ? "" : "*\(inner)*"
        case "code":        return inner.isEmpty ? "" : "`\(inner)`"
        default:            return inner
        }
    }

    // MARK: - Cleanup

    private static func collapseBlankLines(_ s: String) -> String {
        s.replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
         .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
         .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
