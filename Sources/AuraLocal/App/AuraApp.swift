//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import SwiftUI
import AppKit

@main
struct AuraApp: App {
    @StateObject private var env = AppEnvironment()
    @StateObject private var updater = UpdaterService()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(env)
                .environmentObject(env.settingsStore)
                .environmentObject(env.inference)
                .environmentObject(env.telemetry)
                .environmentObject(env.indexing)
                .environmentObject(env.projects)
                .environmentObject(env.chat)
                .environmentObject(env.ollamaControl)
                .environmentObject(env.theme)
                .environmentObject(updater)
                .frame(minWidth: 1080, minHeight: 680)
                .background(WindowConfigurator())
                .onAppear { env.onLaunch() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Chat") { env.chat.newSession(); env.section = .chat }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Inspector") { env.inspectorVisible.toggle() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Makes the host NSWindow transparent so the ambient gradient + vibrancy flow
/// edge-to-edge behind the unified toolbar (the "Mica"/floating-glass look).
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.backgroundColor = NSColor(Theme.Palette.surfaceContainerLowest)
            window.titleVisibility = .hidden
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
