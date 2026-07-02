import SwiftUI
import AppKit

struct ModelZooView: View {
    @EnvironmentObject var inference: InferenceManager
    @EnvironmentObject var telemetry: TelemetryService
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var ollama: OllamaControlService
    @EnvironmentObject var theme: ThemeManager   // re-render in place on theme change

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header
                EmbeddingStatusBanner()
                telemetrySection
                AutoConfigureCard()
                OllamaControlCard()
                activeNode
                repository
            }
            .padding(26)
        }
        .glassPane()
    }

    private var header: some View {
        HStack(alignment: .top) {
            SectionHeader(title: "Model Zoo",
                          subtitle: "Discover and monitor local model runtimes. Connection status, hardware load, and quantized weights across your local mesh.")
            Spacer()
            HStack(spacing: 8) {
                ConnPill(name: "Ollama", online: inference.ollamaOnline)
                ConnPill(name: "LM Studio", online: inference.lmStudioOnline)
                Button { Task { await inference.refresh() } } label: {
                    Image(systemName: "arrow.clockwise").rotationEffect(.degrees(inference.isRefreshing ? 360 : 0))
                }.buttonStyle(GhostGlassButtonStyle())
            }
        }
    }

    private var telemetrySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                MicroLabel(text: "Real-time System Telemetry")
                Spacer()
                LegendDot(color: Theme.Palette.primary, label: "CPU Load")
                LegendDot(color: Theme.Palette.success, label: "Memory")
            }
            HStack(spacing: 14) {
                ChartCard(title: "CPU Load",
                          value: percent(telemetry.snapshot.cpuUsage),
                          values: telemetry.snapshot.history, tint: Theme.Palette.primary)
                ChartCard(title: "Unified Memory",
                          value: gb(telemetry.snapshot.memoryUsed),
                          values: telemetry.snapshot.memHistory, tint: Theme.Palette.success)
            }
        }
    }

    private var activeNode: some View {
        HStack(spacing: 14) {
            ActiveNodeCard()
            VStack(spacing: 14) {
                MiniStat(title: "Context Window", value: "\(settingsStore.settings.contextLength)", unit: "tokens", tint: Theme.Palette.primary)
                MiniStat(title: "Temperature", value: String(format: "%.2f", settingsStore.settings.temperature), unit: "creativity", tint: Theme.Palette.secondary)
            }.frame(width: 200)
            VStack(spacing: 14) {
                MiniStat(title: "Active Provider", value: settingsStore.settings.activeProvider.displayName, unit: "runtime", tint: Theme.Palette.primary)
                MiniStat(title: "Models Discovered", value: "\(inference.models.count)", unit: "available", tint: Theme.Palette.success)
            }.frame(width: 200)
        }
    }

    private var repository: some View {
        VStack(alignment: .leading, spacing: 12) {
            MicroLabel(text: "Active Repository")
            if inference.models.isEmpty {
                Text("No models found. Start Ollama (`ollama serve`) or LM Studio's local server, then refresh.")
                    .font(Theme.Font.body()).foregroundStyle(Theme.Palette.outline)
                    .padding(16).glassCard(radius: Theme.Radius.lg)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                    ForEach(inference.models) { model in
                        ModelCard(model: model,
                                  active: settingsStore.settings.activeChatModel == model.name,
                                  providerOnline: inference.isOnline(model.provider)) {
                            settingsStore.settings.activeProvider = model.provider
                            settingsStore.settings.activeChatModel = model.name
                        }
                    }
                }
            }
        }
    }

    private func percent(_ v: Double) -> String { "\(Int((v*100).rounded()))%" }
    private func gb(_ b: Double) -> String { String(format: "%.1f GB", b / 1_073_741_824) }
}

struct ConnPill: View {
    let name: String; let online: Bool
    var body: some View {
        HStack(spacing: 5) {
            StatusDot(color: online ? Theme.Palette.success : Theme.Palette.error, pulse: online)
            Text(name).font(Theme.Font.bodySm().weight(.medium)).foregroundStyle(Theme.Palette.onSurfaceVariant)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(Theme.Palette.hoverFill))
        .overlay(Capsule().strokeBorder(Theme.glassBorderSoft, lineWidth: 0.5))
    }
}

struct LegendDot: View {
    let color: Color; let label: String
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.outline)
        }
    }
}

struct ChartCard: View {
    let title: String; let value: String; let values: [Double]; let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
                Spacer()
                Text(value).font(Theme.Font.titleSm().monospacedDigit()).foregroundStyle(Theme.Palette.onSurface)
            }
            BarChart(values: values, tint: tint).frame(height: 96)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .glassCard(radius: Theme.Radius.lg)
    }
}

struct BarChart: View {
    let values: [Double]; let tint: Color
    var body: some View {
        GeometryReader { geo in
            let bars = values.suffix(28)
            let count = max(bars.count, 1)
            let spacing: CGFloat = 3
            let barW = max(2, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, v in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient(colors: [tint, tint.opacity(0.45)], startPoint: .top, endPoint: .bottom))
                        .frame(width: barW, height: max(3, geo.size.height * CGFloat(min(1, max(0.02, v)))))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

struct MiniStat: View {
    let title: String; let value: String; let unit: String; let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MicroLabel(text: title)
            Text(value).font(Theme.Font.stat()).foregroundStyle(Theme.Palette.onSurface).lineLimit(1)
            Text(unit).font(Theme.Font.micro()).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(radius: Theme.Radius.lg)
    }
}

/// Live view of the configured chat node: the ring color, spin, and status chip
/// all derive from `InferenceManager.activeNodeState` (provider reachability +
/// catalog + residency), so it can't drift from reality.
struct ActiveNodeCard: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var inference: InferenceManager
    @State private var rotate = false

    private var state: InferenceManager.ActiveNodeState { inference.activeNodeState }

    private var tint: Color {
        switch state {
        case .loaded: return Theme.Palette.success
        case .ready: return Theme.Palette.primary
        case .missing: return Theme.Palette.warning
        case .offline: return Theme.Palette.error
        case .none: return Theme.Palette.outline
        }
    }
    private var statusText: String {
        switch state {
        case .loaded: return "Loaded in memory"
        case .ready: return "Ready · loads on first use"
        case .missing: return "Not in provider catalog"
        case .offline: return "\(settingsStore.settings.activeProvider.displayName) offline"
        case .none: return "No model selected"
        }
    }
    private var spinning: Bool { state == .loaded || state == .ready }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().stroke(tint.opacity(0.15), lineWidth: 8).frame(width: 110, height: 110)
                Circle().trim(from: 0, to: 0.7)
                    .stroke(LinearGradient(colors: [tint, tint.opacity(0.55)],
                                           startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 110, height: 110)
                    .rotationEffect(.degrees(rotate ? 360 : 0))
                Image(systemName: state == .offline ? "cpu" : "cpu.fill")
                    .font(.system(size: 28)).foregroundStyle(tint)
            }
            Text("Current Active Node").font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.outline)
            Text(settingsStore.settings.activeChatModel.isEmpty ? "—" : settingsStore.settings.activeChatModel)
                .font(Theme.Font.titleSm()).foregroundStyle(Theme.Palette.onSurface).lineLimit(1)
            StatusChip(text: statusText, color: tint)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .glassCard(radius: Theme.Radius.lg)
        .onAppear { if spinning { startSpin() } }
        .onChange(of: spinning) { _, now in
            if now { startSpin() } else { stopSpin() }
        }
    }

    private func startSpin() {
        rotate = false
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) { rotate = true }
    }
    private func stopSpin() {
        withAnimation(.linear(duration: 0.2)) { rotate = false }
    }
}

struct ModelCard: View {
    let model: ModelInfo
    let active: Bool
    var providerOnline: Bool = true
    let onActivate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.Palette.primary.opacity(0.16)).frame(width: 30, height: 30)
                    Image(systemName: "shippingbox.fill").font(.system(size: 13)).foregroundStyle(Theme.Palette.primary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.name).font(Theme.Font.body().weight(.semibold))
                        .foregroundStyle(Theme.Palette.onSurface).lineLimit(1)
                    Text(model.provider.displayName).font(Theme.Font.micro()).foregroundStyle(Theme.Palette.outline)
                }
                Spacer()
                if !providerOnline { StatusChip(text: "Server offline", color: Theme.Palette.warning) }
                else if model.loaded { StatusChip(text: "Loaded", color: Theme.Palette.success) }
                else if active { StatusChip(text: "Active", color: Theme.Palette.primary) }
            }

            HStack(spacing: 14) {
                if model.isEmbedding { tag("embedding") }
                if let p = model.parameterSize { tag(p) }
                if let q = model.quantization { tag(q) }
                if let s = model.displaySize { tag(s) }
                if let ctx = model.maxContextLength { tag("\(ctx/1024)K ctx") }
            }

            Button(action: onActivate) {
                Label(active ? "Active" : "Set Active", systemImage: active ? "checkmark.circle.fill" : "play.circle")
                    .font(Theme.Font.bodySm())
            }
            .buttonStyle(active ? AnyButtonStyle(GhostGlassButtonStyle(fullWidth: true))
                                : AnyButtonStyle(PrimaryGlassButtonStyle(fullWidth: true)))
        }
        .padding(14)
        .glassCard(radius: Theme.Radius.lg, selected: active)
    }

    private func tag(_ s: String) -> some View {
        Text(s).font(Theme.Font.tag())
            .foregroundStyle(Theme.Palette.onSurfaceVariant)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(Theme.Palette.hoverFill))
    }
}

/// Type-erased ButtonStyle so we can switch styles conditionally.
struct AnyButtonStyle: ButtonStyle {
    private let makeBodyClosure: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) {
        makeBodyClosure = { config in AnyView(style.makeBody(configuration: config)) }
    }
    func makeBody(configuration: Configuration) -> some View { makeBodyClosure(configuration) }
}

// MARK: - Ollama control (embeddings)

/// In-app control of the local Ollama runtime for embedding models: start/stop the
/// server, pull/update recommended embedding models, unload them, plus a copyable
/// command cheatsheet. Drives `OllamaControlService` (shells out to the `ollama` CLI).
struct OllamaControlCard: View {
    @EnvironmentObject var inference: InferenceManager
    @EnvironmentObject var ollama: OllamaControlService
    @EnvironmentObject var settingsStore: SettingsStore

    private static let cheatsheet = [
        "ollama serve",
        "ollama pull bge-m3",
        "ollama list",
        "ollama ps",
        "ollama stop bge-m3",
    ]

    var body: some View {
        SettingsCard(title: "Ollama Control", symbol: "shippingbox") {
            serverRow
            if !ollama.isInstalled {
                Text("Ollama CLI not found. Install it from ollama.com, then use the commands below.")
                    .font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            modelsSection
            if ollama.isBusy || !ollama.lastLine.isEmpty { activityRow }
            cheatsheetSection
        }
        .task { await ollama.refreshRunning() }
    }

    private var serverRow: some View {
        HStack(spacing: 10) {
            StatusDot(color: inference.ollamaOnline ? Theme.Palette.success : Theme.Palette.error, pulse: inference.ollamaOnline)
            Text(inference.ollamaOnline ? "Server online" : "Server offline")
                .font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
            Spacer()
            Button { ollama.startServer() } label: { Label("Start", systemImage: "play.fill").font(Theme.Font.bodySm()) }
                .buttonStyle(GhostGlassButtonStyle()).disabled(!ollama.isInstalled || inference.ollamaOnline)
            Button { ollama.stopServer() } label: { Label("Stop", systemImage: "stop.fill").font(Theme.Font.bodySm()) }
                .buttonStyle(GhostGlassButtonStyle()).disabled(!ollama.isInstalled || !inference.ollamaOnline)
            Button { ollama.stopServer(); ollama.startServer() } label: { Label("Restart", systemImage: "arrow.clockwise").font(Theme.Font.bodySm()) }
                .buttonStyle(GhostGlassButtonStyle()).disabled(!ollama.isInstalled)
        }
    }

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Embedding models").font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
            ForEach(OllamaControlService.recommendedEmbeddings, id: \.model) { item in
                modelRow(item)
            }
        }
    }

    @ViewBuilder
    private func modelRow(_ item: (model: String, blurb: String)) -> some View {
        let loaded = ollama.running.contains(where: { $0.hasPrefix(item.model) })
        let active = isActiveEmbedding(item.model)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.model).font(Theme.Font.body().weight(.semibold)).foregroundStyle(Theme.Palette.onSurface)
                    Text(item.blurb).font(Theme.Font.micro()).foregroundStyle(Theme.Palette.outline)
                }
                Spacer()
                if active { StatusChip(text: "RAG model", color: Theme.Palette.primary) }
                if loaded { StatusChip(text: "Loaded", color: Theme.Palette.success) }
            }
            HStack(spacing: 8) {
                if !active {
                    Button { setEmbedding(item.model) } label: {
                        Label("Use for RAG", systemImage: "checkmark.circle").font(Theme.Font.bodySm())
                    }.buttonStyle(GhostGlassButtonStyle())
                }
                if loaded {
                    Button { ollama.stopModel(item.model) } label: {
                        Label("Unload", systemImage: "eject").font(Theme.Font.bodySm())
                    }.buttonStyle(GhostGlassButtonStyle())
                } else {
                    Button { ollama.loadModel(item.model) } label: {
                        Label("Load", systemImage: "memorychip").font(Theme.Font.bodySm())
                    }.buttonStyle(GhostGlassButtonStyle()).disabled(!ollama.isInstalled || ollama.isBusy || !inference.ollamaOnline)
                }
                Spacer()
                Button { ollama.pull(item.model) } label: {
                    Label("Pull / Update", systemImage: "arrow.down.circle").font(Theme.Font.bodySm())
                }.buttonStyle(PrimaryGlassButtonStyle()).disabled(!ollama.isInstalled || ollama.isBusy)
            }
        }
        .padding(10)
        .glassCard(radius: Theme.Radius.md, selected: active)
    }

    private func isActiveEmbedding(_ model: String) -> Bool {
        settingsStore.settings.embeddingProvider == .ollama
            && settingsStore.settings.embeddingModel.hasPrefix(model)
    }

    private func setEmbedding(_ model: String) {
        settingsStore.settings.embeddingProvider = .ollama
        settingsStore.settings.embeddingModel = model
        inference.reassessEmbedding()
    }

    private var activityRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let p = ollama.progress { BarMeter(value: p, tint: Theme.Palette.primary) }
            Text(ollama.lastLine).font(Theme.Font.micro()).foregroundStyle(Theme.Palette.outline).lineLimit(1)
        }
    }

    private var cheatsheetSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Terminal commands").font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
            ForEach(Self.cheatsheet, id: \.self) { CommandRow(command: $0) }
        }
    }
}

/// A monospaced command with a one-click copy affordance.
struct CommandRow: View {
    let command: String
    @State private var copied = false
    var body: some View {
        HStack {
            Text(command).font(Theme.Font.code()).foregroundStyle(Theme.Palette.onSurfaceVariant).textSelection(.enabled)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 11))
                    .foregroundStyle(copied ? Theme.Palette.success : Theme.Palette.outline)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.sm).fill(Theme.Palette.fieldFill))
    }
}
