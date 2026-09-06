//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import Foundation

struct DocumentChunk {
    var heading: String?     // breadcrumb of header hierarchy, e.g. "Architecture > State Space Models"
    var text: String
    var ordinal: Int
    var tokenEstimate: Int
}

/// Markdown-aware splitter. Rather than arbitrary character counts, it divides a
/// document by its header hierarchy to preserve structural context, then packs
/// adjacent blocks into chunks bounded by a soft token budget. Fenced code blocks
/// are never split mid-fence.
enum MarkdownChunker {

    /// ~4 chars/token heuristic — good enough for budgeting local context.
    static func estimateTokens(_ s: String) -> Int { max(1, s.count / 4) }

    private struct Block {
        var headingPath: [String]
        var text: String
    }

    /// `docContext` (e.g. "Napoleon (biography) · tags: history, france") is prepended
    /// to every chunk's embedded text so each chunk is self-describing even when read
    /// in isolation — a cheap, model-free form of contextual retrieval that improves
    /// recall on short/ambiguous chunks. It is not counted toward the token budget.
    static func chunk(_ markdown: String, maxTokens: Int = 512, overlap: Int = 64,
                      docContext: String? = nil) -> [DocumentChunk] {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [Block] = []
        var headingStack: [(level: Int, title: String)] = []
        var buffer: [String] = []
        var inFence = false
        var fenceMarker = ""

        func flushBuffer() {
            let text = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeAll()
            guard !text.isEmpty else { return }
            blocks.append(Block(headingPath: headingStack.map { $0.title }, text: text))
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // fence tracking
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = String(trimmed.prefix(3))
                if inFence && marker == fenceMarker {
                    inFence = false
                } else if !inFence {
                    inFence = true; fenceMarker = marker
                }
                buffer.append(line)
                continue
            }

            if !inFence, let level = headerLevel(trimmed) {
                flushBuffer()
                let title = String(trimmed.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
                while let last = headingStack.last, last.level >= level { headingStack.removeLast() }
                headingStack.append((level, title))
                continue
            }
            buffer.append(line)
        }
        flushBuffer()

        // Pack blocks into chunks under the token budget, preserving heading context.
        var chunks: [DocumentChunk] = []
        var ordinal = 0

        for block in blocks {
            let breadcrumb = block.headingPath.filter { !$0.isEmpty }.joined(separator: " › ")
            let pieces = splitToBudget(block.text, maxTokens: maxTokens, overlap: overlap)
            for piece in pieces {
                let header = breadcrumb.isEmpty ? nil : breadcrumb
                let prefix = [docContext, header]
                    .compactMap { ($0?.isEmpty == false) ? $0 : nil }
                    .joined(separator: "\n")
                let prefixed = prefix.isEmpty ? piece : "\(prefix)\n\n\(piece)"
                chunks.append(DocumentChunk(heading: header,
                                            text: prefixed,
                                            ordinal: ordinal,
                                            tokenEstimate: estimateTokens(piece)))
                ordinal += 1
            }
        }
        return chunks
    }

    private static func headerLevel(_ line: String) -> Int? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard hashes >= 1, hashes <= 6 else { return nil }
        // must be followed by a space to be a real ATX header
        let after = line.index(line.startIndex, offsetBy: hashes)
        guard after < line.endIndex, line[after] == " " else { return nil }
        return hashes
    }

    /// Split an oversized section by paragraphs with token overlap.
    private static func splitToBudget(_ text: String, maxTokens: Int, overlap: Int) -> [String] {
        if estimateTokens(text) <= maxTokens { return [text] }
        let paragraphs = text.components(separatedBy: "\n\n")
        var chunks: [String] = []
        var current: [String] = []
        var currentTokens = 0

        for para in paragraphs {
            let t = estimateTokens(para)
            if currentTokens + t > maxTokens, !current.isEmpty {
                chunks.append(current.joined(separator: "\n\n"))
                // carry overlap: keep trailing paragraphs up to `overlap` tokens
                var carried: [String] = []
                var carriedTokens = 0
                for p in current.reversed() {
                    let pt = estimateTokens(p)
                    if carriedTokens + pt > overlap { break }
                    carried.insert(p, at: 0); carriedTokens += pt
                }
                current = carried; currentTokens = carriedTokens
            }
            current.append(para); currentTokens += t
        }
        if !current.isEmpty { chunks.append(current.joined(separator: "\n\n")) }
        return chunks
    }
}
