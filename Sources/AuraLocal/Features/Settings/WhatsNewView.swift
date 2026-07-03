import SwiftUI

/// A readable "What's New" sheet: leads with the current release's notes and can
/// expand to the full history. Content is the bundled `CHANGELOG.md` (the single
/// source of truth, also shown on GitHub Releases), rendered with the same Markdown
/// engine as chat answers. Shown from Settings and auto-presented once after an
/// update (see `RootView`).
struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showFullHistory = false

    private let releaseURL = "https://github.com/srg-sphynx/AuraLocal/releases"

    private var currentNotes: String? { AppInfo.releaseNotes(for: AppInfo.version) }
    private var fullChangelog: String? { AppInfo.changelogMarkdown }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.glassBorderSoft)
            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    if showFullHistory, let full = fullChangelog {
                        MarkdownView(text: full)
                    } else if let notes = currentNotes {
                        MarkdownView(text: notes)
                    } else {
                        fallback
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().overlay(Theme.glassBorderSoft)
            footer
        }
        .frame(width: 580, height: 600)
        .background(Theme.Palette.surface)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.Palette.primary.opacity(0.16)).frame(width: 30, height: 30)
                Image(systemName: "sparkles").font(.system(size: 14)).foregroundStyle(Theme.Palette.primary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("What's New").font(Theme.Font.titleSm()).foregroundStyle(Theme.Palette.onSurface)
                Text("Aura Local \(AppInfo.versionDisplay)")
                    .font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Palette.outline)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if fullChangelog != nil {
                Button { withAnimation(.easeInOut(duration: 0.15)) { showFullHistory.toggle() } } label: {
                    Label(showFullHistory ? "Show this release only" : "Full changelog",
                          systemImage: showFullHistory ? "chevron.up" : "clock.arrow.circlepath")
                        .font(Theme.Font.bodySm())
                }.buttonStyle(GhostGlassButtonStyle())
            }
            if let url = URL(string: releaseURL) {
                Link(destination: url) {
                    Label("All releases", systemImage: "arrow.up.forward.square").font(Theme.Font.bodySm())
                }.buttonStyle(GhostGlassButtonStyle())
            }
            Spacer()
            Button { dismiss() } label: { Text("Done").font(Theme.Font.body().weight(.semibold)) }
                .buttonStyle(PrimaryGlassButtonStyle())
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var fallback: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Release notes for this build aren't bundled.")
                .font(Theme.Font.body()).foregroundStyle(Theme.Palette.onSurface)
            Text("Read the full changelog for every version on GitHub.")
                .font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
        }
    }
}
