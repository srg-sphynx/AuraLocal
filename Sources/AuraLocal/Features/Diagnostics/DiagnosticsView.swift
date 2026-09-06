//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import SwiftUI
import AppKit

/// Diagnostics console: a live view of the in-app log ring buffer (filterable by
/// level/category, copyable, exportable) plus a per-file "Issues" list aggregated
/// across vaults so failed/skipped files surface with a reason.
struct DiagnosticsView: View {
    @EnvironmentObject var projects: ProjectStore
    @EnvironmentObject var indexing: IndexingService
    @EnvironmentObject var theme: ThemeManager   // re-render in place on theme change
    @StateObject private var model = DiagnosticsModel()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header
                issuesSection
                logSection
            }
            .padding(26)
        }
        .glassPane()
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            SectionHeader(title: "Diagnostics",
                          subtitle: "Live logs, warnings and per-file indexing issues. Everything stays on your machine; export a redacted report to share.")
            Spacer()
            HStack(spacing: 8) {
                Button { model.copyToClipboard() } label: { Label("Copy", systemImage: "doc.on.doc").font(Theme.Font.bodySm()) }
                    .buttonStyle(GhostGlassButtonStyle())
                Button { model.exportReport() } label: { Label("Export", systemImage: "square.and.arrow.up").font(Theme.Font.bodySm()) }
                    .buttonStyle(GhostGlassButtonStyle())
                Button { model.clear() } label: { Label("Clear", systemImage: "trash").font(Theme.Font.bodySm()) }
                    .buttonStyle(GhostGlassButtonStyle())
            }
        }
    }

    // MARK: - Issues (per-file failures)

    private var allIssues: [IndexedFile] {
        projects.projects
            .flatMap { indexing.indexedFiles[$0.id] ?? [] }
            .filter { $0.hasIssue }
            .sorted { $0.fileName < $1.fileName }
    }

    @ViewBuilder private var issuesSection: some View {
        let issues = allIssues
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MicroLabel(text: "Indexing Issues")
                Spacer()
                Text("\(issues.count)").font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
            }
            if issues.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.Palette.success)
                    Text("No indexing issues — every source parsed cleanly.")
                        .font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(radius: Theme.Radius.md)
            } else {
                ForEach(issues) { f in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: f.status == .excluded ? "minus.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(f.status == .excluded ? Theme.Palette.warning : Theme.Palette.error)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.fileName).font(Theme.Font.bodySm().weight(.semibold))
                                .foregroundStyle(Theme.Palette.onSurface).lineLimit(1)
                            Text(f.errorMessage ?? "Failed to index.")
                                .font(Theme.Font.micro()).foregroundStyle(Theme.Palette.onSurfaceVariant)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(f.relativePath).font(Theme.Font.micro()).foregroundStyle(Theme.Palette.outline).lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(11).frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(radius: Theme.Radius.md)
                }
            }
        }
    }

    // MARK: - Logs

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                MicroLabel(text: "Logs")
                Spacer()
                Picker("", selection: $model.minLevel) {
                    ForEach(LogLevel.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).frame(width: 240).labelsHidden()
                Menu {
                    Button("All categories") { model.category = nil }
                    Divider()
                    ForEach(LogCategory.allCases, id: \.self) { c in
                        Button(c.displayName) { model.category = c }
                    }
                } label: {
                    Text(model.category?.displayName ?? "All").font(Theme.Font.bodySm())
                }.frame(width: 130)
            }

            let entries = model.filtered
            if entries.isEmpty {
                Text("No log entries at this level yet.")
                    .font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
                    .padding(12)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(entries) { e in LogRow(entry: e) }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Palette.fieldFill))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).strokeBorder(Theme.glassBorderSoft, lineWidth: 0.5))
            }
        }
    }
}

private struct LogRow: View {
    let entry: LogEntry
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.timeFmt.string(from: entry.timestamp))
                .font(Theme.Font.micro().monospacedDigit()).foregroundStyle(Theme.Palette.outline)
            Image(systemName: entry.level.symbol).font(.system(size: 9)).foregroundStyle(color).frame(width: 12)
            Text(entry.category.rawValue).font(Theme.Font.micro().weight(.semibold))
                .foregroundStyle(Theme.Palette.onSurfaceVariant).frame(width: 62, alignment: .leading)
            Text(entry.message).font(Theme.Font.micro()).foregroundStyle(Theme.Palette.onSurface)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
    private var color: Color {
        switch entry.level {
        case .debug: return Theme.Palette.outline
        case .info: return Theme.Palette.primary
        case .warning: return Theme.Palette.warning
        case .error: return Theme.Palette.error
        }
    }
}

/// Polls the (decoupled, thread-safe) `LogStore` on a light timer while the view is
/// visible — logging never forces a main-actor hop, so this can't cause UI jitter.
@MainActor
final class DiagnosticsModel: ObservableObject {
    @Published var entries: [LogEntry] = []
    @Published var minLevel: LogLevel = .info
    @Published var category: LogCategory? = nil

    private var timer: Timer?

    var filtered: [LogEntry] {
        entries.filter { $0.level >= minLevel && (category == nil || $0.category == category) }.suffix(400).reversed()
    }

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    func stop() { timer?.invalidate(); timer = nil }
    private func refresh() { entries = LogStore.shared.snapshot() }

    func clear() { LogStore.shared.clear(); entries = [] }
    func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(LogStore.shared.exportText(), forType: .string)
        ToastCenter.shared.post("Logs copied to clipboard.", level: .info)
    }
    func exportReport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "aura-diagnostics-\(Int(Date().timeIntervalSince1970)).txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? LogStore.shared.exportText().write(to: url, atomically: true, encoding: .utf8)
            ToastCenter.shared.post("Diagnostics exported.", level: .info)
        }
    }
}
