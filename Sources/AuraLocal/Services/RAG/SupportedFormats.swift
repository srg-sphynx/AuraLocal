import Foundation

/// Category of a supported document format. Drives which extractor runs and how
/// the file is presented in the UI (icon + label).
enum FileCategory: String, Codable, CaseIterable {
    case markdown, plain, richText, office, ebook, web, wiki, tabular, pdf, code

    var displayName: String {
        switch self {
        case .markdown: return "Markdown"
        case .plain:    return "Plain text"
        case .richText: return "Rich text"
        case .office:   return "Word"
        case .ebook:    return "EPUB"
        case .web:      return "HTML"
        case .wiki:     return "Wiki"
        case .tabular:  return "Table"
        case .pdf:      return "PDF"
        case .code:     return "Code"
        }
    }

    /// SF Symbol used for file rows in the Knowledge Base / Inspector.
    var symbol: String {
        switch self {
        case .markdown: return "text.alignleft"
        case .plain:    return "doc.text"
        case .richText: return "doc.richtext"
        case .office:   return "doc.fill"
        case .ebook:    return "book"
        case .web:      return "globe"
        case .wiki:     return "link.circle"
        case .tabular:  return "tablecells"
        case .pdf:      return "doc.plaintext"
        case .code:     return "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// Single source of truth for the file types Aura can ingest. `FileIngestor`,
/// `VaultWatcher`, `DocumentExtractor`, and the default `includedExtensions` all
/// read from here so the supported set never drifts out of sync (previously the
/// list was duplicated in three places).
enum SupportedFormats {

    /// Every known extension → its category. Extensions are lowercased.
    static let categoryByExt: [String: FileCategory] = {
        var m: [String: FileCategory] = [:]
        func add(_ cat: FileCategory, _ exts: [String]) { for e in exts { m[e] = cat } }
        add(.markdown, ["md", "markdown", "mdx"])
        add(.plain,    ["txt", "text", "org", "rst", "adoc", "asciidoc", "log"])
        add(.richText, ["rtf", "rtfd"])
        add(.office,   ["docx"])
        add(.ebook,    ["epub"])
        add(.web,      ["html", "htm", "xhtml"])
        add(.wiki,     ["wiki", "mediawiki"])
        add(.tabular,  ["csv", "tsv"])
        add(.pdf,      ["pdf"])
        add(.code,     ["swift", "py", "js", "ts", "tsx", "jsx", "java", "kt", "c", "h",
                        "cpp", "hpp", "cc", "cs", "go", "rs", "rb", "php", "sh", "bash",
                        "zsh", "sql", "json", "yaml", "yml", "toml", "ini", "xml"])
        return m
    }()

    static func category(for ext: String) -> FileCategory? { categoryByExt[ext.lowercased()] }

    static func isSupported(_ ext: String) -> Bool { categoryByExt[ext.lowercased()] != nil }

    /// All supported extensions, sorted (for Settings pickers / docs).
    static var allExtensions: [String] { categoryByExt.keys.sorted() }

    /// Extensions enabled by default. Everything except `.code`, which is opt-in so
    /// large source trees aren't indexed unless the user asks for it.
    static var defaultIncludedExtensions: [String] {
        categoryByExt.filter { $0.value != .code }.keys.sorted()
    }
}
