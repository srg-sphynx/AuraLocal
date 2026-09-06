//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import SwiftUI

struct IndexingView: View {
    @EnvironmentObject var indexing: IndexingService
    @EnvironmentObject var projects: ProjectStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var theme: ThemeManager   // re-render in place on theme change

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header
                HStack(alignment: .top, spacing: 14) {
                    progressCard.frame(width: 300)
                    intensityCard
                }
                sourceConfig
            }
            .padding(26)
        }
        .glassPane()
    }

    private var header: some View {
        HStack(alignment: .top) {
            SectionHeader(title: "Vectorization Engine",
                          subtitle: "Real-time view of the local embedding pipeline. Chunking, vectorization throughput and live source watching.")
            Spacer()
            HStack(spacing: 8) {
                if indexing.isIndexing {
                    Button { indexing.cancel() } label: { Label("Stop", systemImage: "stop.fill").font(Theme.Font.bodySm()) }
                        .buttonStyle(GhostGlassButtonStyle())
                }
                Button {
                    if let p = projects.selectedProject { indexing.index(project: p, force: true) }
                } label: { Label("Force Resync", systemImage: "arrow.triangle.2.circlepath").font(Theme.Font.bodySm()) }
                    .buttonStyle(PrimaryGlassButtonStyle())
                    .disabled(projects.selectedProject == nil || indexing.isIndexing)
            }
        }
    }

    private var progressCard: some View {
        VStack(spacing: 14) {
            MicroLabel(text: indexing.isIndexing ? "Active Task" : "Idle")
            ZStack {
                Circle().stroke(Theme.Palette.primary.opacity(0.12), lineWidth: 12).frame(width: 150, height: 150)
                Circle().trim(from: 0, to: max(0.001, indexing.progress))
                    .stroke(LinearGradient(colors: [Theme.Palette.primary, Theme.Palette.primaryVivid],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 150, height: 150)
                    .animation(.easeOut(duration: 0.3), value: indexing.progress)
                VStack(spacing: 2) {
                    Text("\(Int(indexing.progress * 100))%").font(Theme.Font.displayLg())
                        .foregroundStyle(Theme.Palette.onSurface).monospacedDigit()
                    Text("Complete").font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
                }
            }
            Text(projects.selectedProject.map { "Indexing \($0.name)" } ?? "No vault selected")
                .font(Theme.Font.body().weight(.semibold)).foregroundStyle(Theme.Palette.onSurface).lineLimit(1)
            Text("\(indexing.processedCount) / \(indexing.totalCount) files processed")
                .font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)

            HStack(spacing: 0) {
                stat(String(format: "%.1f MB/s", indexing.throughputMBs), "Throughput")
                Divider().frame(height: 28).overlay(Theme.glassBorderSoft)
                stat("\(indexing.totalChunks())", "Vectors")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .glassCard(radius: Theme.Radius.lg)
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 1) {
            Text(v).font(Theme.Font.body().weight(.semibold).monospacedDigit()).foregroundStyle(Theme.Palette.primary)
            Text(l).font(Theme.Font.micro()).foregroundStyle(Theme.Palette.outline)
        }.frame(maxWidth: .infinity)
    }

    private var intensityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Embedding Intensity").font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
                Spacer()
                LegendDot(color: Theme.Palette.primary, label: "Vectors")
            }
            AreaChart(values: indexing.embeddingIntensity, tint: Theme.Palette.primary)
                .frame(maxHeight: .infinity)
            Text(indexing.statusMessage).font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant).lineLimit(1)
            if let err = indexing.lastError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                    Text(err).font(Theme.Font.bodySm()).lineLimit(2)
                }
                .foregroundStyle(Theme.Palette.error)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.sm).fill(Theme.Palette.errorContainer.opacity(0.25)))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 270)
        .padding(16)
        .glassCard(radius: Theme.Radius.lg)
    }

    private var sourceConfig: some View {
        VStack(alignment: .leading, spacing: 12) {
            MicroLabel(text: "Source Configuration")
            if projects.projects.isEmpty {
                Text("No sources configured.").font(Theme.Font.body()).foregroundStyle(Theme.Palette.outline)
            } else {
                ForEach(projects.projects) { p in
                    HStack(spacing: 12) {
                        Image(systemName: "circle.hexagongrid.fill").foregroundStyle(Theme.Palette.primary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.name).font(Theme.Font.body().weight(.semibold)).foregroundStyle(Theme.Palette.onSurface)
                            Text(p.path).font(Theme.Font.micro()).foregroundStyle(Theme.Palette.outline).lineLimit(1)
                        }
                        Spacer()
                        StatusChip(text: sourceState(p),
                                   color: indexing.isIndexing && indexing.activeProjectID == p.id ? Theme.Palette.primary
                                          : settingsStore.settings.autoRefreshOnSave ? Theme.Palette.success : Theme.Palette.outline)
                        Button { indexing.index(project: p) } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 11)).foregroundStyle(Theme.Palette.outline)
                        }.buttonStyle(.plain)
                    }
                    .padding(12)
                    .glassCard(radius: Theme.Radius.md)
                }
            }
        }
    }

    private func sourceState(_ p: Project) -> String {
        if indexing.isIndexing && indexing.activeProjectID == p.id { return "Syncing" }
        return settingsStore.settings.autoRefreshOnSave ? "Watching" : "Idle"
    }
}

/// Smooth filled area chart (Catmull-ish via simple line) for embedding intensity.
struct AreaChart: View {
    let values: [Double]; let tint: Color
    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if pts.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        for pt in pts { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height))
                        p.closeSubpath()
                    }.fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }.stroke(tint, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                }
            }
        }
    }
    private func points(in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let stepX = size.width / CGFloat(max(values.count - 1, 1))
        return values.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * stepX, y: size.height - CGFloat(min(1, max(0, v))) * size.height * 0.92 - 4)
        }
    }
}
