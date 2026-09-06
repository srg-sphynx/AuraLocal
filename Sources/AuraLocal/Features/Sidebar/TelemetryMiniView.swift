//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import SwiftUI

/// Compact, non-intrusive device telemetry strip for the sidebar.
struct TelemetryMiniView: View {
    @EnvironmentObject var telemetry: TelemetryService

    var body: some View {
        let s = telemetry.snapshot
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                MicroLabel(text: "Device")
                Spacer()
                Text("\(s.coreCount) cores")
                    .font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.outline)
            }

            Sparkline(values: s.history, tint: Theme.Palette.primary)
                .frame(height: 26)

            metric("CPU", value: s.cpuUsage, label: percent(s.cpuUsage), tint: Theme.Palette.primary)
            metric("Memory", value: s.memoryFraction, label: gb(s.memoryUsed) + " / " + gb(s.memoryTotal),
                   tint: Theme.Palette.secondary)
            metric("Unified Pressure", value: s.memoryPressure, label: percent(s.memoryPressure),
                   tint: pressureColor(s.memoryPressure))
        }
        .padding(11)
        .glassCard(radius: Theme.Radius.md)
    }

    private func metric(_ name: String, value: Double, label: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(name).font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
                Spacer()
                Text(label).font(Theme.Font.bodySm().monospacedDigit()).foregroundStyle(Theme.Palette.outline)
            }
            BarMeter(value: value, tint: tint, height: 5)
        }
    }

    private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
    private func gb(_ bytes: Double) -> String { String(format: "%.1fG", bytes / 1_073_741_824) }
    private func pressureColor(_ v: Double) -> Color {
        v > 0.8 ? Theme.Palette.error : (v > 0.55 ? Theme.Palette.warning : Theme.Palette.success)
    }
}

/// Tiny filled sparkline for CPU history.
struct Sparkline: View {
    let values: [Double]
    var tint: Color

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
                    }
                    .fill(LinearGradient(colors: [tint.opacity(0.30), tint.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let maxV = max(values.max() ?? 1, 0.01)
        let stepX = size.width / CGFloat(max(values.count - 1, 1))
        return values.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * stepX, y: size.height - CGFloat(v / maxV) * size.height)
        }
    }
}
