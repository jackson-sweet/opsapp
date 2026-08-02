//
//  BugReportOfflineQueue.swift
//  OPS
//
//  Durable local outbox for bug reports.
//  Persists report envelopes and optional screenshots in the app's documents directory.
//

import Foundation
import UIKit

struct QueuedBugReport: Codable, Equatable {
    let id: String
    let payload: BugReportPayload
    /// Filename only (not full path) — resolved against queueDirectoryURL at load time.
    let screenshotFilename: String?
    let queuedAt: Date
}

@MainActor
final class BugReportOfflineQueue {
    private let maxQueueSize: Int
    private let fileManager: FileManager
    private let queueDirectoryURL: URL
    private let idProvider: () -> String
    private let dateProvider: () -> Date

    private var queueFileURL: URL {
        queueDirectoryURL.appendingPathComponent("queue.json")
    }

    convenience init() {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.init(
            directoryURL: documentsURL.appendingPathComponent("BugReportQueue", isDirectory: true),
            fileManager: fileManager
        )
    }

    init(
        directoryURL: URL,
        maxQueueSize: Int = 10,
        fileManager: FileManager = .default,
        idProvider: @escaping () -> String = { UUID().uuidString.lowercased() },
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.queueDirectoryURL = directoryURL
        self.maxQueueSize = maxQueueSize
        self.fileManager = fileManager
        self.idProvider = idProvider
        self.dateProvider = dateProvider
    }

    // MARK: - Enqueue

    /// Persists a report before it is acknowledged by the UI.
    @discardableResult
    func enqueue(payload: BugReportPayload, screenshot: UIImage?) throws -> QueuedBugReport {
        do {
            try ensureQueueDirectory()
            var queue = try loadQueue()

            guard queue.count < maxQueueSize else {
                throw BugReportError.offlineQueueFull
            }

            let id = idProvider()
            let screenshotFilename = try persistScreenshot(screenshot, reportID: id)
            let item = QueuedBugReport(
                id: id,
                payload: payload,
                screenshotFilename: screenshotFilename,
                queuedAt: dateProvider()
            )

            queue.append(item)
            do {
                try saveQueue(queue)
            } catch {
                if let screenshotFilename {
                    try? fileManager.removeItem(
                        at: queueDirectoryURL.appendingPathComponent(screenshotFilename)
                    )
                }
                throw error
            }

            return item
        } catch let error as BugReportError {
            throw error
        } catch {
            DebugLogger.shared.log(
                "Failed to persist bug report outbox: \(error.localizedDescription)",
                level: .error,
                category: "BugReport"
            )
            throw BugReportError.failedToCreateReport
        }
    }

    // MARK: - Load

    func loadQueue() throws -> [QueuedBugReport] {
        guard fileManager.fileExists(atPath: queueFileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: queueFileURL)
            return try JSONDecoder().decode([QueuedBugReport].self, from: data)
        } catch {
            DebugLogger.shared.log(
                "Failed to read bug report outbox: \(error.localizedDescription)",
                level: .error,
                category: "BugReport"
            )
            throw BugReportError.failedToCreateReport
        }
    }

    /// Resolves a screenshot filename to a full URL in the current container.
    func screenshotURL(for item: QueuedBugReport) -> URL? {
        guard let filename = item.screenshotFilename else { return nil }
        let url = queueDirectoryURL.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return url
    }

    // MARK: - Remove

    /// Removes an item only after its server delivery is confirmed.
    func remove(id: String) throws {
        var queue = try loadQueue()
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }

        let item = queue.remove(at: index)
        do {
            try saveQueue(queue)
        } catch {
            throw BugReportError.failedToCreateReport
        }

        if let filename = item.screenshotFilename {
            let fileURL = queueDirectoryURL.appendingPathComponent(filename)
            do {
                try fileManager.removeItem(at: fileURL)
            } catch where (error as NSError).code != NSFileNoSuchFileError {
                DebugLogger.shared.log(
                    "Failed to remove delivered bug report screenshot: \(error.localizedDescription)",
                    level: .warning,
                    category: "BugReport"
                )
            }
        }
    }

    // MARK: - Persistence

    private func ensureQueueDirectory() throws {
        try fileManager.createDirectory(
            at: queueDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    private func persistScreenshot(_ screenshot: UIImage?, reportID: String) throws -> String? {
        guard let screenshot else { return nil }
        guard let data = screenshot.jpegData(compressionQuality: 0.7) else {
            DebugLogger.shared.log(
                "Failed to encode bug report screenshot to JPEG",
                level: .error,
                category: "BugReport"
            )
            throw BugReportError.failedToCreateReport
        }

        let filename = "\(reportID).jpg"
        do {
            try data.write(
                to: queueDirectoryURL.appendingPathComponent(filename),
                options: .atomic
            )
            return filename
        } catch {
            DebugLogger.shared.log(
                "Failed to write bug report screenshot: \(error.localizedDescription)",
                level: .error,
                category: "BugReport"
            )
            throw error
        }
    }

    private func saveQueue(_ queue: [QueuedBugReport]) throws {
        try ensureQueueDirectory()
        let data = try JSONEncoder().encode(queue)
        try data.write(to: queueFileURL, options: .atomic)
    }
}
