import Foundation
import ZIPFoundation

/// DOCX → Markdown. A `.docx` is a zip; the body lives in `word/document.xml` as
/// WordprocessingML. We stream it with `XMLParser`, mapping `Heading N` paragraph
/// styles to `#` headings and `w:tbl` to Markdown tables. Title comes from
/// `docProps/core.xml` (`dc:title`) when present.
enum DocxExtractor {
    static func extract(_ file: ScannedFile, fallbackTitle: String) throws -> ExtractedDocument {
        let archive: Archive
        do { archive = try ArchiveReader.open(file.url) }
        catch { throw AuraError.archiveUnreadable(path: file.relativePath) }

        guard let body = try? ArchiveReader.entryData(archive, path: "word/document.xml") else {
            throw AuraError.parseFailed(path: file.relativePath, reason: "missing word/document.xml")
        }

        let delegate = DocxBodyParser()
        let parser = XMLParser(data: body)
        parser.delegate = delegate
        parser.parse()

        var title = fallbackTitle
        if let coreData = try? ArchiveReader.entryData(archive, path: "docProps/core.xml"),
           let s = String(data: coreData, encoding: .utf8),
           let t = firstTagText(s, tag: "dc:title"), !t.isEmpty {
            title = t
        }

        let md = delegate.output.trimmingCharacters(in: .whitespacesAndNewlines)
        var warnings: [String] = []
        if md.isEmpty { warnings.append("No extractable text in the Word document.") }
        return ExtractedDocument(markdown: md, title: title, warnings: warnings)
    }

    /// Grab the inner text of the first occurrence of `<tag>…</tag>`.
    private static func firstTagText(_ xml: String, tag: String) -> String? {
        guard let open = xml.range(of: "<\(tag)"),
              let gt = xml.range(of: ">", range: open.upperBound..<xml.endIndex),
              let close = xml.range(of: "</\(tag)>", range: gt.upperBound..<xml.endIndex)
        else { return nil }
        return String(xml[gt.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - WordprocessingML streaming parser

private final class DocxBodyParser: NSObject, XMLParserDelegate {
    private(set) var output = ""

    private var paragraph = ""
    private var currentStyle: String?
    private var inText = false

    // table state
    private var inCell = false
    private var cellText = ""
    private var currentRow: [String] = []
    private var tableRows: [[String]] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "w:tbl":    tableRows = []
        case "w:tr":     currentRow = []
        case "w:tc":     inCell = true; cellText = ""
        case "w:pStyle": currentStyle = attributeDict["w:val"]
        case "w:t":      inText = true
        case "w:tab":    paragraph += "\t"
        case "w:br", "w:cr": paragraph += "\n"
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { paragraph += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        switch elementName {
        case "w:t":  inText = false
        case "w:p":  endParagraph()
        case "w:tc":
            inCell = false
            currentRow.append(cellText.trimmingCharacters(in: .whitespacesAndNewlines))
            cellText = ""
        case "w:tr": tableRows.append(currentRow); currentRow = []
        case "w:tbl": emitTable()
        default: break
        }
    }

    private func endParagraph() {
        let text = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        let style = currentStyle
        paragraph = ""; currentStyle = nil

        if inCell {
            if !text.isEmpty { cellText += (cellText.isEmpty ? "" : " ") + text }
            return
        }
        guard !text.isEmpty else { return }
        if let level = headingLevel(style) {
            output += "\n\n" + String(repeating: "#", count: level) + " " + text + "\n\n"
        } else {
            output += text + "\n\n"
        }
    }

    private func headingLevel(_ style: String?) -> Int? {
        guard let s = style?.lowercased() else { return nil }
        if s == "title" { return 1 }
        if s.hasPrefix("heading") { return min(6, max(1, Int(s.dropFirst("heading".count)) ?? 2)) }
        return nil
    }

    private func emitTable() {
        guard !tableRows.isEmpty else { return }
        let cols = tableRows.map(\.count).max() ?? 0
        func pad(_ r: [String]) -> [String] {
            r.map { $0.replacingOccurrences(of: "|", with: "\\|") } + Array(repeating: "", count: max(0, cols - r.count))
        }
        var md = "\n\n| " + pad(tableRows[0]).joined(separator: " | ") + " |\n"
        md += "| " + Array(repeating: "---", count: cols).joined(separator: " | ") + " |\n"
        for r in tableRows.dropFirst() { md += "| " + pad(r).joined(separator: " | ") + " |\n" }
        output += md + "\n"
        tableRows = []
    }
}
