//
//  AnalyticsEventQueue.swift
//  OPS
//
//  Offline-capable event queue backed by UserDefaults.
//  Pattern follows WizardAnalyticsService offline queue.
//

import Foundation

struct QueuedAnalyticsEvent: Codable {
    let id: String
    let user_id: String?
    let company_id: String?
    let role: String?
    let plan: String?
    let event_type: String
    let event_name: String
    let platform: String
    let app_version: String?
    let device_type: String?
    let os_version: String?
    let session_id: String
    let properties: [String: AnyCodableValue]
    let duration_ms: Int?
    let created_at: String  // ISO 8601
}

/// Type-erased Codable value for JSONB properties
enum AnyCodableValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let val = try? container.decode(Bool.self) { self = .bool(val) }
        else if let val = try? container.decode(Int.self) { self = .int(val) }
        else if let val = try? container.decode(Double.self) { self = .double(val) }
        else if let val = try? container.decode(String.self) { self = .string(val) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let val): try container.encode(val)
        case .int(let val): try container.encode(val)
        case .double(let val): try container.encode(val)
        case .bool(let val): try container.encode(val)
        case .null: try container.encodeNil()
        }
    }
}

final class AnalyticsEventQueue: @unchecked Sendable {

    static let shared = AnalyticsEventQueue()

    private let queueKey = "analytics_event_queue"
    private let maxQueueSize = 1000
    private let lock = NSLock()

    private init() {}

    /// Add an event to the queue. Thread-safe.
    func enqueue(_ event: QueuedAnalyticsEvent) {
        lock.lock()
        defer { lock.unlock() }

        var queue = loadQueue()
        queue.append(event)

        // Cap at maxQueueSize, keeping most recent events
        if queue.count > maxQueueSize {
            queue = Array(queue.suffix(maxQueueSize))
        }

        saveQueue(queue)
    }

    /// Take up to `batchSize` events from the front of the queue.
    /// Events are removed from the queue. If flush fails, call `requeue(_:)`.
    func dequeueBatch(size: Int = 50) -> [QueuedAnalyticsEvent] {
        lock.lock()
        defer { lock.unlock() }

        var queue = loadQueue()
        guard !queue.isEmpty else { return [] }

        let batchCount = min(size, queue.count)
        let batch = Array(queue.prefix(batchCount))
        queue = Array(queue.dropFirst(batchCount))
        saveQueue(queue)

        return batch
    }

    /// Put failed events back at the front of the queue.
    func requeue(_ events: [QueuedAnalyticsEvent]) {
        lock.lock()
        defer { lock.unlock() }

        var queue = loadQueue()
        queue = events + queue

        if queue.count > maxQueueSize {
            queue = Array(queue.suffix(maxQueueSize))
        }

        saveQueue(queue)
    }

    /// Number of events currently queued.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return loadQueue().count
    }

    // MARK: - Persistence

    private func loadQueue() -> [QueuedAnalyticsEvent] {
        guard let data = UserDefaults.standard.data(forKey: queueKey) else { return [] }
        return (try? JSONDecoder().decode([QueuedAnalyticsEvent].self, from: data)) ?? []
    }

    private func saveQueue(_ queue: [QueuedAnalyticsEvent]) {
        if queue.isEmpty {
            UserDefaults.standard.removeObject(forKey: queueKey)
        } else {
            let data = try? JSONEncoder().encode(queue)
            UserDefaults.standard.set(data, forKey: queueKey)
        }
    }
}
