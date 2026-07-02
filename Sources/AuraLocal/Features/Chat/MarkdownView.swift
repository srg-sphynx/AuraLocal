import SwiftUI
import AppKit

/// Lightweight block-level Markdown renderer with fenced code blocks and inline
/// formatting. Inline spans (bold/italic/code/links) use AttributedString; block
/// structure (headers, lists, quotes, code) is handled explicitly so code blocks
/// can carry syntax highlighting and a copy affordance.
struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * Theme.Font.s) {
            ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .code(let lang, let code):
            CodeBlockView(language: lang, code: code)
        case .heading(let level, let content):
            inline(content)
                .font(Theme.Font.mdHeading(level))
                .foregroundStyle(Theme.Palette.onSurface)
                .padding(.top, 2)
        case .quote(let content):
            HStack(spacing: 8) {
                Rectangle().fill(Theme.Palette.primary.opacity(0.6)).frame(width: 2)
                inline(content).foregroundStyle(Theme.Palette.onSurfaceVariant)
            }
        case .bullet(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 7) {
                        Circle().fill(Theme.Palette.primary.opacity(0.8)).frame(width: 4, height: 4).padding(.top, 7)
                        inline(item)
                    }
                }
            }
        case .ordered(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .top, spacing: 7) {
                        Text("\(i + 1).").font(Theme.Font.body().monospacedDigit())
                            .foregroundStyle(Theme.Palette.primary)
                        inline(item)
                    }
                }
            }
        case .paragraph(let content):
            inline(content)
        }
    }

    private func inline(_ content: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attr = try? AttributedString(markdown: content, options: options) {
            return Text(attr)
                .font(Theme.Font.body())
                .foregroundColor(Theme.Palette.onSurface)
        }
        return Text(content).font(Theme.Font.body()).foregroundColor(Theme.Palette.onSurface)
    }
}

// MARK: - Block model + parser

enum MarkdownBlock {
    case paragraph(String)
    case heading(Int, String)
    case code(String?, String)
    case quote(String)
    case bullet([String])
    case ordered([String])

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        var paragraph: [String] = []
        var bullets: [String] = []
        var ordered: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph.removeAll()
            }
        }
        func flushLists() {
            if !bullets.isEmpty { blocks.append(.bullet(bullets)); bullets.removeAll() }
            if !ordered.isEmpty { blocks.append(.ordered(ordered)); ordered.removeAll() }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushParagraph(); flushLists()
                let marker = String(trimmed.prefix(3))
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count {
                    let l = lines[i]
                    if l.trimmingCharacters(in: .whitespaces).hasPrefix(marker) { break }
                    code.append(l); i += 1
                }
                blocks.append(.code(lang.isEmpty ? nil : lang, code.joined(separator: "\n")))
                i += 1
                continue
            }

            if trimmed.isEmpty { flushParagraph(); flushLists(); i += 1; continue }

            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix(while: { $0 == "#" }).count
                if hashes <= 6, trimmed.dropFirst(hashes).first == " " {
                    flushParagraph(); flushLists()
                    blocks.append(.heading(hashes, String(trimmed.dropFirst(hashes)).trimmingCharacters(in: .whitespaces)))
                    i += 1; continue
                }
            }
            if trimmed.hasPrefix(">") {
                flushParagraph(); flushLists()
                blocks.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
                i += 1; continue
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                bullets.append(String(trimmed.dropFirst(2)))
                i += 1; continue
            }
            if let dot = trimmed.firstIndex(of: "."),
               Int(trimmed[..<dot]) != nil,
               trimmed[trimmed.index(after: dot)...].hasPrefix(" ") {
                flushParagraph()
                ordered.append(String(trimmed[trimmed.index(after: dot)...]).trimmingCharacters(in: .whitespaces))
                i += 1; continue
            }

            flushLists()
            paragraph.append(trimmed)
            i += 1
        }
        flushParagraph(); flushLists()
        return blocks
    }
}

// MARK: - Code block with syntax highlighting + copy

struct CodeBlockView: View {
    let language: String?
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text((language?.isEmpty == false ? language! : "code").lowercased())
                    .font(Theme.Font.labelCaps())
                    .foregroundStyle(Theme.Palette.outline)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(Theme.Font.bodySm())
                        .foregroundStyle(copied ? Theme.Palette.success : Theme.Palette.outline)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Theme.Palette.fieldFill)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(SyntaxHighlighter.highlight(code))
                    .font(Theme.Font.code())
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Theme.Palette.fieldFill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
            .strokeBorder(Theme.glassBorderSoft, lineWidth: 0.5))
    }
}

/// Minimal, language-agnostic token coloring (keywords, strings, comments, numbers).
enum SyntaxHighlighter {
    static let keywords: Set<String> = [
        "func","let","var","return","if","else","for","while","in","import","class","struct","enum",
        "guard","switch","case","break","continue","def","public","private","static","await","async",
        "try","throw","throws","catch","do","extension","protocol","self","nil","true","false","new",
        "const","function","print","int","float","double","string","bool","void","null","this","from",
        "as","is","where","with","and","or","not","then","end","begin","type","interface","export","default"
    ]

    static func highlight(_ code: String) -> AttributedString {
        var result = AttributedString()
        for (idx, line) in code.components(separatedBy: "\n").enumerated() {
            if idx > 0 { result += AttributedString("\n") }
            result += highlightLine(line)
        }
        return result
    }

    private static func highlightLine(_ line: String) -> AttributedString {
        // Comment lines
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("#") || trimmed.hasPrefix("--") {
            var a = AttributedString(line); a.foregroundColor = Theme.Palette.outline; return a
        }

        var out = AttributedString()
        var token = ""
        var inString = false
        var stringChar: Character = "\""

        func flushToken() {
            guard !token.isEmpty else { return }
            var a = AttributedString(token)
            if keywords.contains(token) {
                a.foregroundColor = Theme.Palette.primary
            } else if Double(token) != nil {
                a.foregroundColor = Theme.Palette.success
            } else {
                a.foregroundColor = Theme.Palette.onSurface
            }
            out += a
            token = ""
        }

        for ch in line {
            if inString {
                token.append(ch)
                if ch == stringChar {
                    var a = AttributedString(token); a.foregroundColor = Color(hex: 0xE6B450); out += a; token = ""
                    inString = false
                }
                continue
            }
            if ch == "\"" || ch == "'" || ch == "`" {
                flushToken(); inString = true; stringChar = ch; token.append(ch); continue
            }
            if ch.isLetter || ch.isNumber || ch == "_" {
                token.append(ch)
            } else {
                flushToken()
                var a = AttributedString(String(ch)); a.foregroundColor = Theme.Palette.onSurfaceVariant; out += a
            }
        }
        if inString { var a = AttributedString(token); a.foregroundColor = Color(hex: 0xE6B450); out += a }
        else { flushToken() }
        return out
    }
}
