import Foundation
import ZIPFoundation

/// EPUB → Markdown. An `.epub` is a zip of XHTML documents. We read
/// `META-INF/container.xml` to find the OPF package, walk the OPF `spine` in reading
/// order, convert each XHTML chapter via `HTMLToMarkdown`, and stitch them together.
/// Title/author come from the OPF Dublin-Core metadata.
enum EpubExtractor {
    static func extract(_ file: ScannedFile, fallbackTitle: String) throws -> ExtractedDocument {
        let archive: Archive
        do { archive = try ArchiveReader.open(file.url) }
        catch { throw AuraError.archiveUnreadable(path: file.relativePath) }

        guard let containerData = try? ArchiveReader.entryData(archive, path: "META-INF/container.xml"),
              let opfPath = parseContainer(containerData) else {
            throw AuraError.parseFailed(path: file.relativePath, reason: "missing/invalid container.xml")
        }
        guard let opf = try? ArchiveReader.entryData(archive, path: opfPath) else {
            throw AuraError.parseFailed(path: file.relativePath, reason: "missing OPF package \(opfPath)")
        }

        let pkg = parseOPF(opf)
        let opfDir = (opfPath as NSString).deletingLastPathComponent

        var md = ""
        var chapters = 0
        var warnings: [String] = []
        for idref in pkg.spine {
            guard let href = pkg.manifest[idref] else { continue }
            let path = resolve(href: href, relativeTo: opfDir)
            guard let data = try? ArchiveReader.entryData(archive, path: path),
                  let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
            else { continue }
            if let (chapterMD, _) = try? HTMLToMarkdown.convert(html), !chapterMD.isEmpty {
                md += "\n\n" + chapterMD
                chapters += 1
            }
        }

        if chapters == 0 { warnings.append("No readable chapters found in EPUB spine.") }
        var header = ""
        if let author = pkg.creator, !author.isEmpty { header = "By \(author)\n\n" }

        let title = pkg.title?.isEmpty == false ? pkg.title! : fallbackTitle
        return ExtractedDocument(markdown: header + md.trimmingCharacters(in: .whitespacesAndNewlines),
                                 title: title, warnings: warnings)
    }

    // MARK: - Path resolution

    private static func resolve(href: String, relativeTo dir: String) -> String {
        let raw = href.removingPercentEncoding ?? href
        let joined = dir.isEmpty ? raw : dir + "/" + raw
        // Collapse any ../ segments.
        var stack: [String] = []
        for comp in joined.split(separator: "/") {
            if comp == ".." { if !stack.isEmpty { stack.removeLast() } }
            else if comp != "." { stack.append(String(comp)) }
        }
        return stack.joined(separator: "/")
    }

    // MARK: - XML parsing

    private static func parseContainer(_ data: Data) -> String? {
        let d = ContainerParser()
        let p = XMLParser(data: data); p.delegate = d; p.parse()
        return d.rootfilePath
    }

    private struct Package { var manifest: [String: String]; var spine: [String]; var title: String?; var creator: String? }

    private static func parseOPF(_ data: Data) -> Package {
        let d = OPFParser()
        let p = XMLParser(data: data); p.delegate = d; p.parse()
        return Package(manifest: d.manifest, spine: d.spine, title: d.title, creator: d.creator)
    }
}

private final class ContainerParser: NSObject, XMLParserDelegate {
    var rootfilePath: String?
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if (elementName == "rootfile" || elementName.hasSuffix(":rootfile")), rootfilePath == nil {
            rootfilePath = attributeDict["full-path"]
        }
    }
}

private final class OPFParser: NSObject, XMLParserDelegate {
    var manifest: [String: String] = [:]
    var spine: [String] = []
    var title: String?
    var creator: String?
    private var capturing: String?
    private var buffer = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = localName(elementName)
        switch name {
        case "item":
            if let id = attributeDict["id"], let href = attributeDict["href"] { manifest[id] = href }
        case "itemref":
            if let idref = attributeDict["idref"] { spine.append(idref) }
        case "title":   capturing = "title"; buffer = ""
        case "creator": capturing = "creator"; buffer = ""
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturing != nil { buffer += string }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        switch localName(elementName) {
        case "title":   if title == nil { title = buffer.trimmingCharacters(in: .whitespacesAndNewlines) }; capturing = nil
        case "creator": if creator == nil { creator = buffer.trimmingCharacters(in: .whitespacesAndNewlines) }; capturing = nil
        default: break
        }
    }
    private func localName(_ n: String) -> String {
        n.contains(":") ? String(n.split(separator: ":").last ?? "") : n
    }
}
