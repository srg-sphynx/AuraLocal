//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import Foundation

/// Typed, user-surfaceable errors. Carrying structured cases (rather than bare
/// strings) lets the UI show an actionable message and lets logging stay consistent.
enum AuraError: Error, LocalizedError, Equatable {
    case fileUnreadable(path: String)
    case fileTooLarge(path: String, mb: Int, limit: Int)
    case parseFailed(path: String, reason: String)
    case archiveUnreadable(path: String)
    case embeddingFailed(model: String, reason: String)
    case providerOffline(provider: String)
    case database(String)

    var errorDescription: String? {
        switch self {
        case .fileUnreadable(let p):
            return "Couldn’t read “\(p)”."
        case .fileTooLarge(let p, let mb, let limit):
            return "Skipped “\(p)” — \(mb) MB exceeds the \(limit) MB limit."
        case .parseFailed(let p, let reason):
            return "Couldn’t fully parse “\(p)”: \(reason)"
        case .archiveUnreadable(let p):
            return "“\(p)” isn’t a readable archive (corrupt or unsupported)."
        case .embeddingFailed(let model, let reason):
            return "Embedding with “\(model)” failed: \(reason)"
        case .providerOffline(let provider):
            return "\(provider) isn’t reachable."
        case .database(let msg):
            return "Storage error: \(msg)"
        }
    }
}
