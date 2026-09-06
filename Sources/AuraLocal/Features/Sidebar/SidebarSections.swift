//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import SwiftUI

// MARK: - Project / vault directory tree

struct ProjectTreeSection: View {
    @EnvironmentObject var projects: ProjectStore
    @EnvironmentObject var indexing: IndexingService
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                MicroLabel(text: "Vaults")
                Spacer()
                Button { projects.addVault() } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Palette.primary)
                }
                .buttonStyle(.plain)
                .help("Add Obsidian / Markdown vault")
            }

            if projects.projects.isEmpty {
                Text("No vaults yet. Add one to index your notes.")
                    .font(Theme.Font.bodySm())
                    .foregroundStyle(Theme.Palette.outline)
                    .padding(.vertical, 4)
            } else {
                ForEach(projects.projects) { project in
                    VaultRow(project: project,
                             selected: projects.selectedProjectID == project.id,
                             files: indexing.indexedFiles[project.id] ?? [])
                        .onTapGesture { projects.selectedProjectID = project.id }
                }
            }
        }
    }
}

private struct VaultRow: View {
    let project: Project
    let selected: Bool
    let files: [IndexedFile]
    @EnvironmentObject var projects: ProjectStore
    @EnvironmentObject var env: AppEnvironment
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Button { expanded.toggle() } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.Palette.outline)
                        .frame(width: 12)
                }.buttonStyle(.plain)

                Image(systemName: project.kind == .obsidian ? "circle.hexagongrid.fill" : "folder.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(project.kind == .obsidian ? Theme.Palette.primary : Theme.Palette.secondary)
                Text(project.name)
                    .font(Theme.Font.body().weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.Palette.onSurface : Theme.Palette.onSurfaceVariant)
                    .lineLimit(1)
                Spacer(minLength: 2)
                StatusDot(color: statusColor, pulse: project.status == .indexing)
            }
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 5).fill(selected ? Theme.Palette.primary.opacity(0.10) : .clear))
            .contentShape(Rectangle())
            .contextMenu {
                Button("Re-index") { projects.reindex(project) }
                Button("Open in Finder") {
                    if let url = try? BookmarkStore.resolve(project.bookmark).url {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                Divider()
                Button("Remove", role: .destructive) { projects.removeProject(project) }
            }

            if expanded {
                VStack(alignment: .leading, spacing: 1) {
                    if files.isEmpty {
                        Text("— not indexed —").font(Theme.Font.bodySm())
                            .foregroundStyle(Theme.Palette.outline).padding(.leading, 30)
                    } else {
                        ForEach(files.prefix(40)) { f in
                            HStack(spacing: 6) {
                                Image(systemName: icon(for: f.ext)).font(.system(size: 9))
                                    .foregroundStyle(Theme.Palette.outline)
                                Text(f.fileName).font(Theme.Font.bodySm()).lineLimit(1)
                                    .foregroundStyle(Theme.Palette.onSurfaceVariant)
                                Spacer(minLength: 0)
                                Text("\(f.chunkCount)").font(Theme.Font.bodySm().monospacedDigit())
                                    .foregroundStyle(Theme.Palette.outline)
                            }
                            .padding(.leading, 30).padding(.trailing, 4).padding(.vertical, 1)
                        }
                        if files.count > 40 {
                            Text("+ \(files.count - 40) more").font(Theme.Font.bodySm())
                                .foregroundStyle(Theme.Palette.outline).padding(.leading, 30)
                        }
                    }
                }
            }
        }
    }

    private var statusColor: Color {
        switch project.status {
        case .synced: return Theme.Palette.success
        case .indexing: return Theme.Palette.primary
        case .error: return Theme.Palette.error
        default: return Theme.Palette.outline
        }
    }
    private func icon(for ext: String) -> String {
        switch ext {
        case "pdf": return "doc.richtext"
        case "md", "markdown": return "doc.text"
        default: return "doc"
        }
    }
}

// MARK: - Chat history

struct ChatHistorySection: View {
    @EnvironmentObject var chat: ChatViewModel
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroLabel(text: "History")
            ForEach(chat.sessions.prefix(20)) { session in
                ChatHistoryRow(session: session, active: chat.currentSessionID == session.id) {
                    chat.selectSession(session.id); env.section = .chat
                }
            }
        }
    }
}

private struct ChatHistoryRow: View {
    let session: ChatSession
    let active: Bool
    let action: () -> Void
    @EnvironmentObject var chat: ChatViewModel
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 10))
                    .foregroundStyle(active ? Theme.Palette.primary : Theme.Palette.outline)
                Text(session.title)
                    .font(Theme.Font.bodySm().weight(active ? .semibold : .regular))
                    .foregroundStyle(active ? Theme.Palette.onSurface : Theme.Palette.onSurfaceVariant)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if hover {
                    Button { chat.deleteSession(session.id) } label: {
                        Image(systemName: "trash").font(.system(size: 9)).foregroundStyle(Theme.Palette.outline)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 5)
                .fill(active ? Theme.Palette.primary.opacity(0.10) : (hover ? Theme.Palette.hoverFill : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
