import Foundation
import ZIPFoundation

/// Thin helper around ZIPFoundation for the zip-container formats (DOCX, EPUB).
enum ArchiveReader {

    static func open(_ url: URL) throws -> Archive {
        try Archive(url: url, accessMode: .read)
    }

    /// Read a single entry's full bytes, or nil if the entry is absent.
    static func entryData(_ archive: Archive, path: String) throws -> Data? {
        // Try the literal path first, then a percent-decoded variant (EPUB hrefs are
        // often percent-encoded while the zip entry name is not, or vice-versa).
        let candidates = [path, path.removingPercentEncoding].compactMap { $0 }
        for candidate in candidates {
            guard let entry = archive[candidate] else { continue }
            var data = Data()
            _ = try archive.extract(entry) { data.append($0) }
            return data
        }
        return nil
    }
}
