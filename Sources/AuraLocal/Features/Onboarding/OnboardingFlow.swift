import SwiftUI

/// Current onboarding content version. Bump to re-show onboarding after a release
/// that changes setup meaningfully.
let currentOnboardingVersion = 1

/// First-run guided setup + walkthrough. Presented as a dimmed overlay from
/// `RootView` when onboarding hasn't been completed. Each step reflects **live**
/// app state (provider reachability, embedding readiness, vault presence) so the
/// user is guided through a working configuration rather than a static slideshow.
struct OnboardingFlow: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var inference: InferenceManager
    @EnvironmentObject var projects: ProjectStore
    @EnvironmentObject var indexing: IndexingService
    @EnvironmentObject var settingsStore: SettingsStore

    @State private var step = 0
    private let lastStep = 4

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .background(.ultraThinMaterial)

            VStack(spacing: 0) {
                progressDots
                card
                controls
            }
            .frame(width: 560)
            .padding(28)
            .glassPane(radius: Theme.Radius.xl, glow: true)
            .frame(maxWidth: 620)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    // MARK: - Steps

    @ViewBuilder private var card: some View {
        switch step {
        case 0: welcomeStep
        case 1: providerStep
        case 2: embeddingStep
        case 3: vaultStep
        default: finishStep
        }
    }

    private var welcomeStep: some View {
        stepScaffold(icon: "sparkles", tint: Theme.Palette.primary,
                     title: "Welcome to Aura Local",
                     subtitle: "A private, on-device RAG assistant. Your notes and documents never leave your Mac — indexing and chat run entirely against your local models.") {
            VStack(alignment: .leading, spacing: 10) {
                bullet("lock.fill", "100% local — no cloud, no telemetry.")
                bullet("doc.text.magnifyingglass", "Chats grounded in your own files, with citations.")
                bullet("bolt.fill", "Markdown, PDF, Word, HTML, EPUB, wiki & more.")
            }
        }
    }

    private var providerStep: some View {
        stepScaffold(icon: "cpu", tint: Theme.Palette.primary,
                     title: "Connect a local model",
                     subtitle: "Aura talks to LM Studio (chat) and Ollama (embeddings). Start at least one, then we’ll detect it automatically.") {
            VStack(spacing: 10) {
                providerRow("LM Studio", online: inference.lmStudioOnline, hint: "Recommended for chat")
                providerRow("Ollama", online: inference.ollamaOnline, hint: "Recommended for embeddings (bge-m3)")
                Button { Task { await inference.refresh() } } label: {
                    Label("Re-check connections", systemImage: "arrow.clockwise").font(Theme.Font.bodySm())
                }.buttonStyle(GhostGlassButtonStyle()).padding(.top, 2)
            }
        }
    }

    private var embeddingStep: some View {
        stepScaffold(icon: "square.stack.3d.up.fill", tint: Theme.Palette.primary,
                     title: "Pick an embedding model",
                     subtitle: "Embeddings power semantic search. bge-m3 on Ollama is a great default. Keyword search works even before this is ready.") {
            VStack(alignment: .leading, spacing: 12) {
                EmbeddingStatusBanner()
                HStack(spacing: 8) {
                    Image(systemName: inference.embeddingReady ? "checkmark.seal.fill" : "circle.dashed")
                        .foregroundStyle(inference.embeddingReady ? Theme.Palette.success : Theme.Palette.outline)
                    Text(inference.embeddingReady
                         ? "Embedding model ready — semantic search is on."
                         : "Load an embedding model to enable semantic search.")
                        .font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
                }
            }
        }
    }

    private var vaultStep: some View {
        stepScaffold(icon: "folder.fill.badge.plus", tint: Theme.Palette.primary,
                     title: "Add your first source",
                     subtitle: "Point Aura at a folder or Obsidian vault. It’s parsed, chunked and vectorized locally.") {
            VStack(alignment: .leading, spacing: 12) {
                Button { projects.addVault() } label: {
                    Label("Choose a folder…", systemImage: "plus").font(Theme.Font.body())
                }.buttonStyle(PrimaryGlassButtonStyle())

                if projects.projects.isEmpty {
                    Text("No source added yet — you can also do this later from the Knowledge Base.")
                        .font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
                } else {
                    ForEach(projects.projects) { p in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Palette.success)
                            Text(p.name).font(Theme.Font.bodySm().weight(.semibold)).foregroundStyle(Theme.Palette.onSurface)
                            Spacer()
                            Text(indexing.isIndexing ? "indexing…" : "\(indexing.chunkCount(for: p.id)) chunks")
                                .font(Theme.Font.micro()).foregroundStyle(Theme.Palette.onSurfaceVariant)
                        }
                    }
                }
            }
        }
    }

    private var finishStep: some View {
        stepScaffold(icon: "checkmark.seal.fill", tint: Theme.Palette.success,
                     title: "You’re all set",
                     subtitle: "Ask a question in Chat and Aura will retrieve the most relevant passages from your sources and cite them.") {
            VStack(alignment: .leading, spacing: 10) {
                bullet("bubble.left.and.text.bubble.right", "Chat — ask grounded questions.")
                bullet("books.vertical", "Knowledge Base — manage sources & indexing.")
                bullet("stethoscope", "Diagnostics — logs and per-file issues.")
            }
        }
    }

    // MARK: - Chrome

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(0...lastStep, id: \.self) { i in
                Capsule()
                    .fill(i == step ? Theme.Palette.primary : Theme.Palette.outlineVariant)
                    .frame(width: i == step ? 18 : 6, height: 6)
                    .animation(.easeInOut(duration: 0.2), value: step)
            }
        }.padding(.bottom, 18)
    }

    private var controls: some View {
        HStack {
            if step > 0 {
                Button { withAnimation { step -= 1 } } label: { Text("Back").font(Theme.Font.bodySm()) }
                    .buttonStyle(GhostGlassButtonStyle())
            }
            Button { finish() } label: { Text("Skip").font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.outline) }
                .buttonStyle(.plain)
            Spacer()
            Button {
                if step >= lastStep { finish() } else { withAnimation { step += 1 } }
            } label: {
                Label(step >= lastStep ? "Start chatting" : "Next",
                      systemImage: step >= lastStep ? "arrow.right.circle.fill" : "arrow.right")
                    .font(Theme.Font.body().weight(.semibold))
            }.buttonStyle(PrimaryGlassButtonStyle())
        }
        .padding(.top, 20)
    }

    private func finish() {
        settingsStore.settings.hasCompletedOnboarding = true
        settingsStore.settings.onboardingVersion = currentOnboardingVersion
        env.section = .chat
    }

    // MARK: - Bits

    private func stepScaffold<Content: View>(icon: String, tint: Color, title: String, subtitle: String,
                                             @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.16)).frame(width: 48, height: 48)
                Image(systemName: icon).font(.system(size: 22, weight: .semibold)).foregroundStyle(tint)
            }
            Text(title).font(Theme.Font.headline()).foregroundStyle(Theme.Palette.onSurface)
            Text(subtitle).font(Theme.Font.body()).foregroundStyle(Theme.Palette.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
            content().padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 240, alignment: .top)
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Theme.Palette.primary).frame(width: 18)
            Text(text).font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.onSurfaceVariant)
        }
    }

    private func providerRow(_ name: String, online: Bool, hint: String) -> some View {
        HStack(spacing: 10) {
            StatusDot(color: online ? Theme.Palette.success : Theme.Palette.outline, pulse: !online)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(Theme.Font.bodySm().weight(.semibold)).foregroundStyle(Theme.Palette.onSurface)
                Text(hint).font(Theme.Font.micro()).foregroundStyle(Theme.Palette.outline)
            }
            Spacer()
            Text(online ? "Connected" : "Not detected")
                .font(Theme.Font.bodySm()).foregroundStyle(online ? Theme.Palette.success : Theme.Palette.onSurfaceVariant)
        }
        .padding(11)
        .glassCard(radius: Theme.Radius.md)
    }
}
