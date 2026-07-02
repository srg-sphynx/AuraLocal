import SwiftUI

struct ChatView: View {
    @EnvironmentObject var chat: ChatViewModel
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var inference: InferenceManager

    var body: some View {
        VStack(spacing: 0) {
            ChatHeaderBar()
            Divider().overlay(Theme.glassBorderSoft)
            messages
            if chat.ragEnabled {
                EmbeddingStatusBanner(compact: true)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 4)
            }
            ChatComposer()
        }
        .glassPane()
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if let session = chat.currentSession {
                        if session.messages.isEmpty {
                            EmptyChatState()
                                .padding(.top, 60)
                        }
                        ForEach(session.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
            }
            .onChange(of: chat.currentSession?.messages.last?.text) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: chat.currentSessionID) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}

// MARK: - Header

struct ChatHeaderBar: View {
    @EnvironmentObject var chat: ChatViewModel
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var inference: InferenceManager
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        HStack(spacing: 12) {
            Text(chat.currentSession?.title ?? "Aura")
                .font(Theme.Font.titleSm())
                .foregroundStyle(Theme.Palette.onSurface)
                .lineLimit(1)

            ModelPickerChip()

            Spacer()

            if chat.isGenerating {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(String(format: "%.0f tok/s", chat.liveTokensPerSecond))
                        .font(Theme.Font.bodySm().monospacedDigit())
                        .foregroundStyle(Theme.Palette.success)
                }
            }

            Toggle(isOn: $chat.ragEnabled) {
                Label("RAG", systemImage: "doc.text.magnifyingglass")
                    .font(Theme.Font.bodySm())
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Theme.Palette.primaryVivid)
            .help("Retrieve from your vault before answering")

            Button { env.inspectorVisible.toggle() } label: {
                Image(systemName: "sidebar.trailing")
                    .foregroundStyle(env.inspectorVisible ? Theme.Palette.primary : Theme.Palette.onSurfaceVariant)
            }
            .buttonStyle(.plain)
            .help("Toggle Context inspector")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

struct ModelPickerChip: View {
    @EnvironmentObject var inference: InferenceManager
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        Menu {
            if inference.chatModels.isEmpty {
                Text("No models found — is Ollama / LM Studio running?")
            }
            ForEach(inference.chatModels) { model in
                Button {
                    settingsStore.settings.activeProvider = model.provider
                    settingsStore.settings.activeChatModel = model.name
                } label: {
                    Label("\(model.name)  ·  \(model.provider.displayName)",
                          systemImage: settingsStore.settings.activeChatModel == model.name ? "checkmark" : "cpu")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(inference.isActiveOnline ? Theme.Palette.success : Theme.Palette.error)
                    .frame(width: 6, height: 6)
                Text(settingsStore.settings.activeChatModel.isEmpty ? "Select model"
                     : settingsStore.settings.activeChatModel)
                    .font(Theme.Font.bodySm().weight(.medium))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
            }
            .foregroundStyle(Theme.Palette.onSurfaceVariant)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Theme.Palette.hoverFill))
            .overlay(Capsule().strokeBorder(Theme.glassBorderSoft, lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Empty state

struct EmptyChatState: View {
    @EnvironmentObject var projects: ProjectStore
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.Palette.primary.opacity(0.12)).frame(width: 64, height: 64)
                Image(systemName: "sparkles").font(.system(size: 26))
                    .foregroundStyle(Theme.Palette.primary)
            }
            Text("Ask Aura anything")
                .font(Theme.Font.headline()).foregroundStyle(Theme.Palette.onSurface)
            Text(projects.selectedProject == nil
                 ? "Add a vault from the sidebar to ground answers in your notes."
                 : "RAG is grounding answers in “\(projects.selectedProject!.name)”.")
                .font(Theme.Font.body())
                .foregroundStyle(Theme.Palette.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
    }
}
