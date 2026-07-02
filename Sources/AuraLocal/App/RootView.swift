import SwiftUI
import AppKit

/// Three-pane shell: floating sidebar · main section · collapsible inspector.
/// Also the theme coordinator — applies the persisted theme config and rebuilds
/// the tree (`.id(theme.revision)`) when the user changes appearance.
struct RootView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var settingsStore: SettingsStore
    @ObservedObject private var toasts = ToastCenter.shared
    @Environment(\.colorScheme) private var systemScheme

    private var showOnboarding: Bool { !settingsStore.settings.hasCompletedOnboarding }

    var body: some View {
        ZStack {
            Theme.ambientBackground
            HStack(spacing: Theme.Space.windowInset) {
                SidebarView()
                    .frame(width: 244)

                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if env.inspectorVisible {
                    InspectorPanel()
                        .frame(width: 288)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(Theme.Space.windowInset)
            // Panes run to the top of the window — the traffic lights float over the
            // sidebar header (which pads itself to clear them). No dead header band.

            ToastOverlay(toasts: toasts)

            if showOnboarding {
                OnboardingFlow().zIndex(10)
            }
        }
        .id(theme.revision)
        .preferredColorScheme(theme.preferredColorScheme)
        .animation(.easeInOut(duration: 0.22), value: env.inspectorVisible)
        .animation(.easeInOut(duration: 0.18), value: env.section)
        .animation(.easeInOut(duration: 0.25), value: showOnboarding)
        .onAppear { theme.apply(settingsStore.settings.theme, systemDark: systemScheme == .dark) }
        .onChange(of: settingsStore.settings.theme) { _, new in
            theme.apply(new, systemDark: systemScheme == .dark)
        }
        .onChange(of: systemScheme) { _, new in
            theme.apply(settingsStore.settings.theme, systemDark: new == .dark)
        }
        // Track the system text size: re-resolve on every activation (apply no-ops
        // when nothing actually changed, so this is free in the common case).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            theme.apply(settingsStore.settings.theme, systemDark: systemScheme == .dark)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch env.section {
        case .chat:        ChatView()
        case .knowledge:   KnowledgeBaseView()
        case .modelZoo:    ModelZooView()
        case .indexing:    IndexingView()
        case .diagnostics: DiagnosticsView()
        case .settings:    SettingsView()
        }
    }
}

/// Bottom-trailing stack of auto-dismissing toasts.
private struct ToastOverlay: View {
    @ObservedObject var toasts: ToastCenter
    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Spacer()
            ForEach(toasts.toasts) { toast in
                HStack(spacing: 9) {
                    Image(systemName: toast.level.symbol).font(.system(size: 12)).foregroundStyle(tint(toast.level))
                    Text(toast.message).font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurface)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { toasts.dismiss(toast.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.Palette.outline)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .frame(maxWidth: 360, alignment: .leading)
                .glassPane(radius: Theme.Radius.md, glow: false)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toasts.toasts)
        .allowsHitTesting(!toasts.toasts.isEmpty)
    }
    private func tint(_ level: LogLevel) -> Color {
        switch level {
        case .error: return Theme.Palette.error
        case .warning: return Theme.Palette.warning
        default: return Theme.Palette.primary
        }
    }
}
