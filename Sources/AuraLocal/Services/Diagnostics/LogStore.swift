//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import Foundation

/// Severity of a log entry.
enum LogLevel: Int, Comparable, Codable, CaseIterable {
    case debug, info, warning, error

    var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
    var symbol: String {
        switch self {
        case .debug: return "ladybug"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }
    static func < (l: LogLevel, r: LogLevel) -> Bool { l.rawValue < r.rawValue }
}

/// Subsystem area a log entry belongs to.
enum LogCategory: String, CaseIterable, Codable {
    case indexing, retrieval, inference, db, ui, ingest, general

    var displayName: String { rawValue.capitalized }
}

struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    var level: LogLevel
    var category: LogCategory
    var message: String

    init(level: LogLevel, category: LogCategory, message: String, timestamp: Date = Date()) {
        self.level = level
        self.category = category
        self.message = message
        self.timestamp = timestamp
    }
}

/// A bounded, thread-safe ring buffer of recent log entries. Decoupled from SwiftUI
/// on purpose: `record` is cheap and callable from any thread (including the hot
/// off-main indexing task), and the Diagnostics view pulls `snapshot()` on a light
/// timer rather than every log forcing a main-actor hop. This keeps logging from
/// ever becoming the source of UI jitter.
final class LogStore: @unchecked Sendable {
    static let shared = LogStore()

    private let capacity = 4000
    private let lock = NSLock()
    private var buffer: [LogEntry] = []

    func record(_ entry: LogEntry) {
        lock.lock()
        buffer.append(entry)
        if buffer.count > capacity { buffer.removeFirst(buffer.count - capacity) }
        lock.unlock()
    }

    /// Newest-last copy of the buffer, optionally filtered.
    func snapshot(minLevel: LogLevel = .debug, category: LogCategory? = nil) -> [LogEntry] {
        lock.lock(); defer { lock.unlock() }
        return buffer.filter { $0.level >= minLevel && (category == nil || $0.category == category) }
    }

    func clear() { lock.lock(); buffer.removeAll(); lock.unlock() }

    /// Plain-text export (redacted: messages are logged already-redacted by callers).
    func exportText() -> String {
        let fmt = ISO8601DateFormatter()
        return snapshot().map { e in
            "\(fmt.string(from: e.timestamp))  \(e.level.label.padding(toLength: 5, withPad: " ", startingAt: 0))  [\(e.category.rawValue)]  \(e.message)"
        }.joined(separator: "\n")
    }
}
