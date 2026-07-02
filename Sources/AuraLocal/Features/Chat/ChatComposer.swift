import SwiftUI

struct ChatComposer: View {
    @EnvironmentObject var chat: ChatViewModel
    @EnvironmentObject var projects: ProjectStore
    @EnvironmentObject var inference: InferenceManager
    @State private var focused: Bool = false
    @State private var composerHeight: CGFloat = 24
    /// Local draft: typing must not publish through the ChatViewModel on every
    /// keystroke (that re-renders every observer — sidebar, header, inspector).
    @State private var draft: String = ""

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Message Aura…")
                            .font(Theme.Font.body())
                            .foregroundStyle(Theme.Palette.outline)
                            .padding(.horizontal, 4).padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                    ComposerTextView(text: $draft, height: $composerHeight,
                                     isFocused: $focused, onSend: send)
                        .frame(height: composerHeight)
                        .padding(.horizontal, 4).padding(.vertical, 6)
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Palette.fieldFill))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .strokeBorder(focused ? Theme.Palette.primary.opacity(0.6) : Theme.glassBorderSoft,
                                  lineWidth: focused ? 1 : 0.5))

                if chat.isGenerating {
                    Button(action: chat.stop) {
                        Image(systemName: "stop.fill").foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Theme.Palette.error.opacity(0.85)))
                    }.buttonStyle(.plain)
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(canSend ? Theme.Palette.primaryVivid : Theme.Palette.surfaceContainerHigh))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canSend)
                }
            }

            HStack(spacing: 10) {
                ragBadge
                if let p = projects.selectedProject {
                    Label(p.name, systemImage: "circle.hexagongrid")
                        .font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.outline)
                }
                Spacer()
                Text("↩ to send · ⇧↩ for a new line")
                    .font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.outline)
            }
            .padding(.horizontal, 2)
        }
        .padding(14)
        .onAppear { focused = true }
    }

    private var ragBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: chat.ragEnabled ? "doc.text.magnifyingglass" : "minus.circle")
                .font(.system(size: 10))
            Text(chat.ragEnabled ? "RAG ON" : "RAG OFF")
                .font(Theme.Font.labelCaps())
        }
        .foregroundStyle(chat.ragEnabled ? Theme.Palette.success : Theme.Palette.outline)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill((chat.ragEnabled ? Theme.Palette.success : Theme.Palette.outline).opacity(0.12)))
        .onTapGesture { chat.ragEnabled.toggle() }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private func send() {
        guard canSend, !chat.isGenerating else { return }
        chat.draft = draft
        chat.send()
        draft = ""
    }
}
