//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import Foundation
import Combine

/// Lightweight, non-blocking notification surface. Any code can post a transient
/// message (embedding failed, provider went offline, files skipped) and it appears
/// as a toast that auto-dismisses. A singleton so services without a view context
/// (IndexingService, InferenceManager) can post directly.
@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        var level: LogLevel
        var message: String
    }

    @Published private(set) var toasts: [Toast] = []

    func post(_ message: String, level: LogLevel = .info) {
        // Coalesce identical back-to-back messages.
        if toasts.last?.message == message { return }
        let toast = Toast(level: level, message: message)
        toasts.append(toast)
        if toasts.count > 4 { toasts.removeFirst(toasts.count - 4) }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_500_000_000)
            self?.dismiss(toast.id)
        }
    }

    func dismiss(_ id: UUID) { toasts.removeAll { $0.id == id } }
}
