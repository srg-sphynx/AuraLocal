import SwiftUI

/// Suggests a chat model, embedding model, context length, and chunk size based on
/// installed models + system RAM, with one-click apply. Powered by `ModelAdvisor`.
struct AutoConfigureCard: View {
    @EnvironmentObject var inference: InferenceManager
    @EnvironmentObject var telemetry: TelemetryService
    @EnvironmentObject var settingsStore: SettingsStore

    private var ramGB: Double { max(4, telemetry.snapshot.memoryTotal / 1_073_741_824) }

    var body: some View {
        let rec = ModelAdvisor.recommend(installed: inference.models, ramGB: ramGB)
        SettingsCard(title: "Auto-Configure", symbol: "wand.and.stars") {
            Text("Recommendations from your installed models and ~\(Int(ramGB.rounded())) GB of RAM.")
                .font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)

            HStack(spacing: 10) {
                recPill("Chat", rec.chatLabel, installed: rec.chatModel != nil)
                recPill("Embedding", rec.embeddingLabel, installed: rec.embeddingModel != nil)
            }
            HStack(spacing: 10) {
                recPill("Context", "\(rec.contextLength)", installed: true)
                recPill("Chunk", "\(rec.chunkTokens) tok", installed: true)
            }

            if !rec.notes.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(rec.notes, id: \.self) { n in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "info.circle").font(.system(size: 9)).foregroundStyle(Theme.Palette.outline)
                            Text(n).font(Theme.Font.scaled(10.5)).foregroundStyle(Theme.Palette.outline)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button {
                    var s = settingsStore.settings
                    ModelAdvisor.apply(rec, to: &s)
                    settingsStore.settings = s
                    inference.reassessEmbedding()
                } label: { Label("Apply Recommended", systemImage: "checkmark.circle").font(Theme.Font.bodySm()) }
                .buttonStyle(PrimaryGlassButtonStyle())
            }
        }
    }

    private func recPill(_ label: String, _ value: String, installed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                MicroLabel(text: label)
                if !installed {
                    Text("pull").font(Theme.Font.scaled(8, weight: .bold))
                        .foregroundStyle(Theme.Palette.warning)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(Theme.Palette.warning.opacity(0.15)))
                }
            }
            Text(value).font(Theme.Font.body().weight(.semibold)).foregroundStyle(Theme.Palette.onSurface).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .glassCard(radius: Theme.Radius.md)
    }
}
