import SwiftUI

/// Surfaces embedding-model readiness so the user knows when semantic search is
/// active vs. degraded to keyword search — and what to do about it. Shows nothing
/// when the model is ready (silent success). Detection only: it never auto-loads.
struct EmbeddingStatusBanner: View {
    @EnvironmentObject var inference: InferenceManager
    @EnvironmentObject var settingsStore: SettingsStore
    var compact: Bool = false

    var body: some View {
        let status = inference.embeddingStatus
        if !status.isReady {
            let tint = Self.tint(for: status)
            HStack(spacing: 9) {
                Image(systemName: Self.icon(for: status))
                    .font(.system(size: compact ? 11 : 13))
                    .foregroundStyle(tint)
                Text(status.message(model: settingsStore.settings.embeddingModel,
                                    provider: settingsStore.settings.embeddingProvider))
                    .font(compact ? Theme.Font.bodySm() : Theme.Font.body())
                    .foregroundStyle(Theme.Palette.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Button {
                    Task { await inference.refresh() }
                } label: {
                    Text(status == .loading ? "Checking…" : "Recheck").font(Theme.Font.bodySm())
                }
                .buttonStyle(GhostGlassButtonStyle())
            }
            .padding(.horizontal, 12).padding(.vertical, compact ? 7 : 9)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(tint.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).strokeBorder(tint.opacity(0.28), lineWidth: 0.5))
        }
    }

    static func tint(for s: EmbeddingStatus) -> Color {
        switch s {
        case .providerOffline, .error: return Theme.Palette.error
        case .notConfigured, .modelNotFound, .notLoaded: return Theme.Palette.warning
        case .loading: return Theme.Palette.primary
        case .ready: return Theme.Palette.success
        }
    }

    static func icon(for s: EmbeddingStatus) -> String {
        switch s {
        case .providerOffline: return "wifi.slash"
        case .notConfigured: return "questionmark.circle"
        case .modelNotFound: return "exclamationmark.magnifyingglass"
        case .notLoaded: return "powersleep"
        case .loading: return "hourglass"
        case .ready: return "checkmark.seal.fill"
        case .error: return "exclamationmark.triangle"
        }
    }
}
