import Foundation
import AppKit

/// Opens or reveals a cited source file straight from the chat. The app is
/// non-sandboxed, so a plain `NSWorkspace.open` on the resolved URL is enough; we
/// still resolve the vault root through its security-scoped bookmark first so a
/// moved/renamed vault folder keeps working. Failures post a toast rather than
/// throwing — a missing source shouldn't interrupt the conversation.
@MainActor
enum SourceOpener {

    /// Resolve `relativePath` inside `project`'s vault to an on-disk file URL, or nil
    /// if the vault can't be resolved or the file no longer exists.
    static func fileURL(project: Project?, relativePath: String) -> URL? {
        guard let project else { return nil }
        let root = (try? BookmarkStore.resolve(project.bookmark).url)
            ?? URL(fileURLWithPath: project.path)
        let url = root.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Open the source in its default application (Preview for PDFs, etc.).
    static func open(project: Project?, relativePath: String, fileName: String) {
        guard let url = fileURL(project: project, relativePath: relativePath) else {
            notFound(fileName); return
        }
        if !NSWorkspace.shared.open(url) {
            ToastCenter.shared.post("Couldn't open “\(fileName)”.", level: .warning)
        }
    }

    /// Reveal the source in Finder (Right-click affordance / fallback).
    static func reveal(project: Project?, relativePath: String, fileName: String) {
        guard let url = fileURL(project: project, relativePath: relativePath) else {
            notFound(fileName); return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private static func notFound(_ fileName: String) {
        ToastCenter.shared.post("“\(fileName)” isn't where it was indexed — it may have moved or been renamed.",
                                level: .warning)
    }
}
