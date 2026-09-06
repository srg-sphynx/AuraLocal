//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        if message.role == .user {
            userBubble
        } else {
            assistantBubble
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 60)
            Text(message.text)
                .font(Theme.Font.body())
                .foregroundStyle(Theme.Palette.onPrimaryReadable)
                .textSelection(.enabled)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.Palette.primaryVivid.opacity(0.9),
                                                      Theme.Palette.primaryVivid.opacity(0.72)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .strokeBorder(Theme.glassBorder, lineWidth: 0.5))
        }
    }

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Theme.Palette.primary.opacity(0.16)).frame(width: 22, height: 22)
                    Image(systemName: "sparkle").font(.system(size: 11)).foregroundStyle(Theme.Palette.primary)
                }
                Text("Aura Intelligence")
                    .font(Theme.Font.bodySm().weight(.semibold))
                    .foregroundStyle(Theme.Palette.onSurfaceVariant)
                if message.isStreaming {
                    TypingDots()
                }
                Spacer()
                if let model = message.modelName, !model.isEmpty {
                    Text(model).font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.outline)
                }
            }

            if message.text.isEmpty && message.isStreaming {
                Text("Thinking…").font(Theme.Font.body()).foregroundStyle(Theme.Palette.outline)
            } else if message.isStreaming {
                // Plain text while streaming — re-parsing the full Markdown tree on
                // every token is the main source of jank during generation.
                Text(message.text)
                    .font(Theme.Font.body())
                    .foregroundStyle(Theme.Palette.onSurface)
                    .textSelection(.enabled)
            } else {
                MarkdownView(text: message.text)
                    .textSelection(.enabled)
            }

            if !message.citations.isEmpty {
                CitationStrip(citations: message.citations)
            }

            if !message.isStreaming, let tps = message.tokensPerSecond, tps > 0 {
                HStack(spacing: 10) {
                    Label(String(format: "%.1f tok/s", tps), systemImage: "speedometer")
                    if let count = message.tokenCount { Label("\(count) tokens", systemImage: "number") }
                }
                .font(Theme.Font.bodySm())
                .foregroundStyle(Theme.Palette.outline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(radius: Theme.Radius.lg)
    }
}

struct CitationStrip: View {
    let citations: [Citation]
    private var citedCount: Int { citations.filter { $0.usedInAnswer == true }.count }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                MicroLabel(text: "Relevant files · \(citations.count)")
                if citedCount > 0 {
                    Label("\(citedCount) cited", systemImage: "quote.opening")
                        .font(Theme.Font.micro().weight(.semibold))
                        .foregroundStyle(Theme.Palette.primary)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(citations) { c in CitationCard(citation: c) }
                }
            }
        }
    }
}

/// A single source chip under an answer. Click it to open the exact file that
/// grounded the answer (Preview/editor); right-click to reveal it in Finder.
struct CitationCard: View {
    let citation: Citation
    @EnvironmentObject var projects: ProjectStore
    @State private var hover = false

    private var project: Project? { projects.project(id: citation.projectID) }
    /// The answer explicitly referenced this file — give it a persistent accent.
    private var isCited: Bool { citation.usedInAnswer == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: isCited ? "quote.opening" : SourceIcon.symbol(for: citation.fileName))
                    .font(.system(size: 10)).foregroundStyle(Theme.Palette.primary)
                Text(citation.fileName).font(Theme.Font.bodySm().weight(.semibold))
                    .foregroundStyle(Theme.Palette.onSurface).lineLimit(1)
                Spacer(minLength: 4)
                // Hover swaps the score for an "open" glyph so the chip reads as clickable.
                if hover {
                    Image(systemName: "arrow.up.forward.app").font(.system(size: 10))
                        .foregroundStyle(Theme.Palette.primary)
                } else {
                    Text(String(format: "%.0f%%", citation.score * 100))
                        .font(Theme.Font.bodySm().monospacedDigit())
                        .foregroundStyle(Theme.Palette.success)
                }
            }
            if let h = citation.heading {
                Text(h).font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.primary).lineLimit(1)
            }
            Text(citation.snippet)
                .font(Theme.Font.bodySm())
                .foregroundStyle(Theme.Palette.onSurfaceVariant)
                .lineLimit(2)
        }
        .padding(9)
        .frame(width: 220, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md)
            .fill(isCited ? Theme.Palette.primary.opacity(0.10) : Theme.Palette.fieldFill))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md)
            .strokeBorder(hover || isCited ? Theme.Palette.primary.opacity(hover ? 0.55 : 0.4)
                                           : Theme.glassBorderSoft,
                          lineWidth: hover || isCited ? 1 : 0.5))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .onTapGesture {
            SourceOpener.open(project: project, relativePath: citation.filePath, fileName: citation.fileName)
        }
        .onHover { hover = $0 }
        .help("Open \(citation.fileName)")
        .contextMenu {
            Button("Open") {
                SourceOpener.open(project: project, relativePath: citation.filePath, fileName: citation.fileName)
            }
            Button("Reveal in Finder") {
                SourceOpener.reveal(project: project, relativePath: citation.filePath, fileName: citation.fileName)
            }
        }
    }
}

/// Maps a file name to an SF Symbol by extension, so a source chip / row reads at a
/// glance (PDF vs. doc vs. sheet vs. web).
enum SourceIcon {
    static func symbol(for fileName: String) -> String {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "pdf":                              return "doc.richtext"
        case "md", "markdown", "txt", "text":    return "doc.text"
        case "docx", "doc", "rtf", "pages":      return "doc"
        case "csv", "tsv", "xlsx", "xls", "numbers": return "tablecells"
        case "html", "htm", "xhtml":             return "globe"
        case "epub":                             return "book"
        case "json", "yaml", "yml", "xml":       return "curlybraces"
        default:                                  return "doc.text"
        }
    }
}

struct TypingDots: View {
    @State private var phase = 0.0
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { i in
                Circle().fill(Theme.Palette.primary)
                    .frame(width: 4, height: 4)
                    .opacity(phase == Double(i) ? 1 : 0.3)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4).repeatForever()) { phase = 2 }
        }
    }
}
