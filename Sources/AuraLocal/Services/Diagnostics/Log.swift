import Foundation
import os

/// Facade over `os.Logger` that also mirrors entries into `LogStore` for the in-app
/// Diagnostics console. Use the pre-made category loggers (`Log.indexing`, …) rather
/// than constructing your own. Messages are emitted `.public` — callers must not put
/// secrets (API keys, full file contents) into log text.
struct Log: Sendable {
    let category: LogCategory
    private let logger: Logger

    static let subsystem = "com.aura.local"

    init(_ category: LogCategory) {
        self.category = category
        self.logger = Logger(subsystem: Log.subsystem, category: category.rawValue)
    }

    static let indexing  = Log(.indexing)
    static let retrieval = Log(.retrieval)
    static let inference = Log(.inference)
    static let db        = Log(.db)
    static let ui        = Log(.ui)
    static let ingest    = Log(.ingest)
    static let general   = Log(.general)

    func debug(_ message: @autoclosure () -> String)   { emit(.debug, message()) }
    func info(_ message: @autoclosure () -> String)     { emit(.info, message()) }
    func warning(_ message: @autoclosure () -> String)  { emit(.warning, message()) }
    func error(_ message: @autoclosure () -> String)    { emit(.error, message()) }

    /// Convenience for logging a typed error at `.error` level.
    func error(_ error: Error) { emit(.error, (error as? LocalizedError)?.errorDescription ?? "\(error)") }

    private func emit(_ level: LogLevel, _ message: String) {
        switch level {
        case .debug:   logger.debug("\(message, privacy: .public)")
        case .info:    logger.info("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        case .error:   logger.error("\(message, privacy: .public)")
        }
        LogStore.shared.record(LogEntry(level: level, category: category, message: message))
    }
}
