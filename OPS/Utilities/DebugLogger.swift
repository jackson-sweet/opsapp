//
//  DebugLogger.swift
//  OPS
//
//  Debug logging with rolling buffer for bug reports.
//

import Foundation
import SwiftData

// MARK: - Log Entry

struct LogEntry: Codable {
    let timestamp: String
    let level: String
    let message: String
    let category: String

    init(level: String, message: String, category: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestamp = formatter.string(from: Date())
        self.level = level
        self.message = message
        self.category = category
    }

    var asDictionary: [String: String] {
        ["timestamp": timestamp, "level": level, "message": message, "category": category]
    }
}

// MARK: - Debug Logger

class DebugLogger {
    static let shared = DebugLogger()
    var projectInfo: String

    /// Rolling buffer of recent log entries for bug reports
    private var logBuffer: [LogEntry] = []
    private let bufferCapacity = 100
    private let bufferLock = NSLock()

    private init() { projectInfo = "" }

    // MARK: - Structured Logging (New)

    /// Log a message with level and category. Prints to console and records in rolling buffer.
    func log(_ message: String, level: LogLevel = .info, category: String = "General") {
        let entry = LogEntry(level: level.rawValue, message: message, category: category)

        // Print to console with tag format
        let prefix: String
        switch level {
        case .info: prefix = "ℹ️"
        case .warning: prefix = "⚠️"
        case .error: prefix = "❌"
        case .debug: prefix = "🔍"
        }
        print("[\(category.uppercased())] \(prefix) \(message)")

        // Add to rolling buffer
        bufferLock.lock()
        logBuffer.append(entry)
        if logBuffer.count > bufferCapacity {
            logBuffer.removeFirst(logBuffer.count - bufferCapacity)
        }
        bufferLock.unlock()
    }

    /// Get a snapshot of the current log buffer for bug reports
    func getLogSnapshot() -> [[String: String]] {
        bufferLock.lock()
        let snapshot = logBuffer.map { $0.asDictionary }
        bufferLock.unlock()
        return snapshot
    }

    /// Clear the log buffer
    func clearBuffer() {
        bufferLock.lock()
        logBuffer.removeAll()
        bufferLock.unlock()
    }

    // MARK: - Legacy Methods (Preserved)

    func logProjectAccess(project: Project?, location: String, projectId: String? = nil) {
        if let project = project {
            autoreleasepool {
                do {
                    _ = project.id
                    projectInfo = "Project(\(project.id))"
                } catch {
                    projectInfo = "INVALIDATED PROJECT (caught error)"
                }
            }
        } else {
            projectInfo = "nil"
        }

        log("Project access at \(location): \(projectInfo) (requested: \(projectId ?? "none"))", level: .debug, category: "ProjectAccess")
    }

    func logModelStorage(type: String, location: String, count: Int? = nil) {
        if let count = count {
            log("Storing \(count) \(type) models at \(location)", level: .debug, category: "ModelStorage")
        } else {
            log("Storing \(type) model at \(location)", level: .debug, category: "ModelStorage")
        }
    }

    func logCritical(_ message: String, location: String) {
        log("\(location): \(message)", level: .error, category: "Critical")

        // Log full call stack for critical issues
        print("[CALL STACK]")
        Thread.callStackSymbols.prefix(15).forEach { symbol in
            print("  \(symbol)")
        }
    }
}

// MARK: - Log Level

enum LogLevel: String, Codable {
    case info = "info"
    case warning = "warning"
    case error = "error"
    case debug = "debug"
}
