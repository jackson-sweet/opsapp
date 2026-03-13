//
//  BugReportOfflineQueue.swift
//  OPS
//
//  Lightweight offline queue for bug reports.
//  Persists to a JSON file in the app's documents directory.
//  Screenshots saved as temporary JPEG files alongside.
//

import UIKit
import Foundation

struct QueuedBugReport: Codable {
    let id: String
    let payload: BugReportPayload
    /// Filename only (not full path) — resolved against queueDirectoryURL at load time
    let screenshotFilename: String?
    let queuedAt: Date
}

final class BugReportOfflineQueue {
    private let maxQueueSize = 10
    private let fileManager = FileManager.default

    private var queueDirectoryURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("BugReportQueue", isDirectory: true)
    }

    private var queueFileURL: URL {
        queueDirectoryURL.appendingPathComponent("queue.json")
    }

    init() {
        // Ensure directory exists
        try? fileManager.createDirectory(at: queueDirectoryURL, withIntermediateDirectories: true)
    }

    // MARK: - Enqueue

    func enqueue(payload: BugReportPayload, screenshot: UIImage?) throws {
        var queue = loadQueue()

        guard queue.count < maxQueueSize else {
            throw BugReportError.offlineQueueFull
        }

        let id = UUID().uuidString

        // Save screenshot to temp file
        var screenshotFilename: String?
        if let screenshot = screenshot,
           let data = screenshot.jpegData(compressionQuality: 0.7) {
            let filename = "\(id).jpg"
            let imageURL = queueDirectoryURL.appendingPathComponent(filename)
            do {
                try data.write(to: imageURL)
                screenshotFilename = filename
            } catch {
                DebugLogger.shared.log("Failed to write bug report screenshot: \(error.localizedDescription)", level: .warning, category: "BugReport")
            }
        } else if screenshot != nil {
            DebugLogger.shared.log("Failed to encode bug report screenshot to JPEG", level: .warning, category: "BugReport")
        }

        let item = QueuedBugReport(
            id: id,
            payload: payload,
            screenshotFilename: screenshotFilename,
            queuedAt: Date()
        )

        queue.append(item)
        saveQueue(queue)
    }

    // MARK: - Load

    func loadQueue() -> [QueuedBugReport] {
        guard fileManager.fileExists(atPath: queueFileURL.path),
              let data = try? Data(contentsOf: queueFileURL),
              let queue = try? JSONDecoder().decode([QueuedBugReport].self, from: data) else {
            return []
        }
        return queue
    }

    /// Resolve a screenshot filename to a full URL in the current container
    func screenshotURL(for item: QueuedBugReport) -> URL? {
        guard let filename = item.screenshotFilename else { return nil }
        let url = queueDirectoryURL.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return url
    }

    // MARK: - Remove

    func remove(id: String) {
        var queue = loadQueue()
        if let index = queue.firstIndex(where: { $0.id == id }) {
            let item = queue[index]

            // Delete screenshot file
            if let filename = item.screenshotFilename {
                let fileURL = queueDirectoryURL.appendingPathComponent(filename)
                try? fileManager.removeItem(at: fileURL)
            }

            queue.remove(at: index)
            saveQueue(queue)
        }
    }

    // MARK: - Persistence

    private func saveQueue(_ queue: [QueuedBugReport]) {
        guard let data = try? JSONEncoder().encode(queue) else { return }
        try? data.write(to: queueFileURL, options: .atomic)
    }

    /// Number of queued reports
    var count: Int {
        loadQueue().count
    }
}
