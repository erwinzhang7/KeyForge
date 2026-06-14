import Foundation
import OSLog

public enum LogLevel: String, Codable, CaseIterable, Sendable {
    case none, errors, all
}

/// Thin wrapper around os.Logger with adjustable verbosity.
/// Buffer keeps the last 500 messages in memory so the user can export them from Settings.
public final class Logger: @unchecked Sendable {
    public static let shared = Logger()

    private let osLog = os.Logger(subsystem: "com.local.keyforge", category: "engine")
    private let lock = NSLock()
    private var buffer: [String] = []
    private let maxBuffer = 500

    public var level: LogLevel = .all

    public func info(_ message: String) {
        guard level == .all else { return }
        osLog.info("\(message, privacy: .public)")
        append("[INFO] \(message)")
    }

    public func error(_ message: String) {
        guard level != .none else { return }
        osLog.error("\(message, privacy: .public)")
        append("[ERROR] \(message)")
    }

    public func debug(_ message: String) {
        guard level == .all else { return }
        osLog.debug("\(message, privacy: .public)")
        append("[DEBUG] \(message)")
    }

    private func append(_ entry: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "\(ts) \(entry)"
        lock.lock()
        buffer.append(line)
        if buffer.count > maxBuffer { buffer.removeFirst(buffer.count - maxBuffer) }
        lock.unlock()
    }

    public func exportBuffer() -> String {
        lock.lock()
        let snapshot = buffer
        lock.unlock()
        return snapshot.joined(separator: "\n")
    }
}
