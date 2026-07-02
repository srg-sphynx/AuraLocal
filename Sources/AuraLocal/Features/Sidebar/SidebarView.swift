import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var inference: InferenceManager
    @EnvironmentObject var chat: ChatViewModel
    @EnvironmentObject var projects: ProjectStore
    @EnvironmentObject var theme: ThemeManager   // re-render in place on theme change

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.glassBorderSoft).padding(.horizontal, 12)

            // Primary navigation
            VStack(spacing: 2) {
                ForEach(AppSection.allCases) { section in
                    NavRow(section: section, isActive: env.section == section) {
                        env.section = section
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)

            Divider().overlay(Theme.glassBorderSoft).padding(.horizontal, 12)

            // Contextual middle: projects + chat history
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    ProjectTreeSection()
                    ChatHistorySection()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }

            Spacer(minLength: 0)

            // Pinned telemetry + footer
            VStack(spacing: 10) {
                TelemetryMiniView()
                footer
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .glassPane(material: .sidebar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.Palette.primary, Theme.Palette.primaryVivid],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 26, height: 26)
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Aura Local")
                        .font(Theme.Font.titleSm())
                        .foregroundStyle(Theme.Palette.onSurface)
                    Text("Local RAG · LLM")
                        .font(Theme.Font.bodySm())
                        .foregroundStyle(Theme.Palette.outline)
                }
                Spacer()
            }

            // Local mesh status
            HStack(spacing: 6) {
                MicroLabel(text: "Local Mesh")
                Spacer()
                meshStatus
            }

            Button {
                env.chat.newSession(); env.section = .chat
            } label: {
                Label("New Chat", systemImage: "plus")
            }
            .buttonStyle(PrimaryGlassButtonStyle(fullWidth: true))
        }
        .padding(14)
        .padding(.top, 24) // clear the floating traffic lights (hidden titlebar)
    }

    private var meshStatus: some View {
        Group {
            if inference.ollamaOnline {
                StatusChip(text: "Ollama", color: Theme.Palette.success)
            } else if inference.lmStudioOnline {
                StatusChip(text: "LM Studio", color: Theme.Palette.success)
            } else {
                StatusChip(text: "Offline", color: Theme.Palette.error)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 2) {
            FooterLink(title: "Documentation", symbol: "book")
            FooterLink(title: "GitHub", symbol: "chevron.left.forwardslash.chevron.right")
        }
    }
}

private struct NavRow: View {
    let section: AppSection
    let isActive: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(isActive ? Theme.Palette.primary : Theme.Palette.onSurfaceVariant)
                Text(section.rawValue)
                    .font(Theme.Font.body().weight(isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Theme.Palette.onSurface : Theme.Palette.onSurfaceVariant)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(isActive ? Theme.Palette.primary.opacity(0.14) : (hover ? Theme.Palette.hoverFill : .clear))
            )
            .overlay(alignment: .leading) {
                if isActive {
                    Capsule().fill(Theme.Palette.primary).frame(width: 3, height: 16).padding(.leading, 1)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct FooterLink: View {
    let title: String
    let symbol: String
    @State private var hover = false
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 11)).frame(width: 16)
            Text(title).font(Theme.Font.bodySm())
            Spacer()
        }
        .foregroundStyle(hover ? Theme.Palette.onSurface : Theme.Palette.outline)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 5).fill(hover ? Theme.Palette.hoverFill : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}
