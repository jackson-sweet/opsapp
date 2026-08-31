//
//  AnalyticsEventQueue.swift
//  OPS
//
//  Versioned, privacy-bounded analytics contract and durable offline queue.
//

import Foundation

enum AnalyticsEventContract {
    static let schemaVersion = 1
    static let maxEventNameLength = 80
    static let maxPropertyCount = 25
    static let maxPropertyStringBytes = 256
    static let maxQueueSize = 1_000

    static var environment: String {
        #if DEBUG
        return "development"
        #else
        return "production"
        #endif
    }

    private static let allowedPropertyKeys: Set<String> = [
        "action", "age_seconds", "attempts", "context", "count", "currency",
        "empty_visit_bundles", "entity", "entity_type", "entry_point",
        "error_type", "flow_type", "has_address", "has_company", "has_email",
        "has_phone", "has_schedule", "has_thumbnail", "import_method",
        "is_pre_signup", "last_step", "launch_type", "lead_created",
        "lead_requests", "method", "new_status", "notification_type",
        "old_status", "operation_count", "operation_type", "path", "plan",
        "price", "project_count", "reason", "resume_context", "retry_count",
        "scheme", "screen_index", "session_duration_ms", "source", "step",
        "step_count", "sync_phase", "tab_index", "tab_name", "task_type",
        "team_size", "trial_days", "user_type", "variant", "visit_count",
        "was_running"
    ]

    static func isValidEventName(_ name: String) -> Bool {
        guard name.utf8.count <= maxEventNameLength else { return false }
        return name.range(
            of: "^[a-z][a-z0-9_]*$",
            options: .regularExpression
        ) != nil
    }

    static func sanitizeProperties(_ input: [String: Any]) -> [String: AnyCodableValue] {
        var result: [String: AnyCodableValue] = [:]
        for key in input.keys.sorted() where result.count < maxPropertyCount {
            guard allowedPropertyKeys.contains(key), let rawValue = input[key] else { continue }
            guard let value = sanitizeValue(rawValue, for: key) else { continue }
            result[key] = value
        }
        return result
    }

    private static func sanitizeValue(_ value: Any, for key: String) -> AnyCodableValue? {
        switch value {
        case let value as Bool:
            return .bool(value)
        case let value as Int:
            return .int(value)
        case let value as Double where value.isFinite:
            return .double(value)
        case let value as Float where value.isFinite:
            return .double(Double(value))
        case let value as String:
            return sanitizeString(value, for: key).map(AnyCodableValue.string)
        default:
            return nil
        }
    }

    private static func sanitizeString(_ value: String, for key: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !containsPII(trimmed) else { return nil }
        if key == "path" && !["owner", "crew", "unknown"].contains(trimmed) {
            return nil
        }

        var bounded = String(trimmed.prefix(maxPropertyStringBytes))
        while bounded.utf8.count > maxPropertyStringBytes {
            bounded.removeLast()
        }
        return bounded
    }

    private static func containsPII(_ value: String) -> Bool {
        if value.range(
            of: #"\b[^\s@]+@[^\s@]+\.[^\s@]+\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return true
        }
        if value.range(
            of: #"(?:https?://|www\.)\S+"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return true
        }
        if value.range(
            of: #"[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return true
        }

        let digits = value.filter(\.isNumber)
        return (10...15).contains(digits.count)
    }
}

struct QueuedAnalyticsEvent: Codable, Equatable {
    /// Local queue ownership only. RPC encoding deliberately strips this field.
    let expected_subject: String?
    /// New unauthenticated events may be claimed exactly once by the first
    /// authenticated subject. Legacy ownerless events decode as false.
    let is_preauth: Bool
    let id: String
    let event_type: String
    let event_name: String
    let app_version: String?
    let device_type: String?
    let os_version: String?
    let session_id: String
    let properties: [String: AnyCodableValue]
    let duration_ms: Int?
    let schema_version: Int
    let environment: String
    let created_at: String

    init(
        expected_subject: String? = nil,
        is_preauth: Bool = false,
        id: String,
        event_type: String,
        event_name: String,
        app_version: String?,
        device_type: String?,
        os_version: String?,
        session_id: String,
        properties: [String: AnyCodableValue],
        duration_ms: Int?,
        schema_version: Int = AnalyticsEventContract.schemaVersion,
        environment: String = AnalyticsEventContract.environment,
        created_at: String
    ) {
        self.expected_subject = expected_subject
        self.is_preauth = is_preauth
        self.id = id
        self.event_type = event_type
        self.event_name = event_name
        self.app_version = app_version
        self.device_type = device_type
        self.os_version = os_version
        self.session_id = session_id
        self.properties = properties
        self.duration_ms = duration_ms
        self.schema_version = schema_version
        self.environment = environment
        self.created_at = created_at
    }

    private enum CodingKeys: String, CodingKey {
        case expected_subject, is_preauth, id, event_type, event_name, app_version, device_type, os_version
        case session_id, properties, duration_ms, schema_version, environment, created_at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        expected_subject = try container.decodeIfPresent(String.self, forKey: .expected_subject)
        is_preauth = try container.decodeIfPresent(Bool.self, forKey: .is_preauth) ?? false
        id = try container.decode(String.self, forKey: .id)
        event_type = try container.decode(String.self, forKey: .event_type)
        event_name = try container.decode(String.self, forKey: .event_name)
        app_version = try container.decodeIfPresent(String.self, forKey: .app_version)
        device_type = try container.decodeIfPresent(String.self, forKey: .device_type)
        os_version = try container.decodeIfPresent(String.self, forKey: .os_version)
        session_id = try container.decode(String.self, forKey: .session_id)
        properties = try container.decode([String: AnyCodableValue].self, forKey: .properties)
        duration_ms = try container.decodeIfPresent(Int.self, forKey: .duration_ms)
        schema_version = try container.decodeIfPresent(Int.self, forKey: .schema_version)
            ?? AnalyticsEventContract.schemaVersion
        environment = try container.decodeIfPresent(String.self, forKey: .environment)
            ?? "production"
        created_at = try container.decode(String.self, forKey: .created_at)
    }

    func claimed(by subject: String) -> QueuedAnalyticsEvent {
        QueuedAnalyticsEvent(
            expected_subject: subject,
            is_preauth: false,
            id: id,
            event_type: event_type,
            event_name: event_name,
            app_version: app_version,
            device_type: device_type,
            os_version: os_version,
            session_id: session_id,
            properties: properties,
            duration_ms: duration_ms,
            schema_version: schema_version,
            environment: environment,
            created_at: created_at
        )
    }
}

struct AnalyticsAppendRPCParams: Encodable {
    let p_events: [QueuedAnalyticsEvent]
    let p_expected_subject: String
    let p_schema_version: Int
    let p_environment: String

    private enum CodingKeys: String, CodingKey {
        case p_events, p_expected_subject, p_schema_version, p_environment
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(p_events.map(AnalyticsServerEvent.init), forKey: .p_events)
        try container.encode(p_expected_subject, forKey: .p_expected_subject)
        try container.encode(p_schema_version, forKey: .p_schema_version)
        try container.encode(p_environment, forKey: .p_environment)
    }
}

private struct AnalyticsServerEvent: Encodable {
    let id: String
    let event_type: String
    let event_name: String
    let app_version: String?
    let device_type: String?
    let os_version: String?
    let session_id: String
    let properties: [String: AnyCodableValue]
    let duration_ms: Int?
    let created_at: String

    init(_ event: QueuedAnalyticsEvent) {
        id = event.id
        event_type = event.event_type
        event_name = event.event_name
        app_version = event.app_version
        device_type = event.device_type
        os_version = event.os_version
        session_id = event.session_id
        properties = event.properties
        duration_ms = event.duration_ms
        created_at = event.created_at
    }
}

enum AnyCodableValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

final class AnalyticsEventQueue: @unchecked Sendable {

    static let shared = AnalyticsEventQueue()

    private let queueKey: String
    private let defaults: UserDefaults
    private let lock = NSLock()

    init(
        queueKey: String = "analytics_event_queue",
        defaults: UserDefaults = .standard
    ) {
        self.queueKey = queueKey
        self.defaults = defaults
    }

    func enqueue(_ event: QueuedAnalyticsEvent) {
        lock.lock()
        defer { lock.unlock() }

        var queue = loadQueue()
        queue.append(event)
        if queue.count > AnalyticsEventContract.maxQueueSize {
            queue = Array(queue.suffix(AnalyticsEventContract.maxQueueSize))
        }
        saveQueue(queue)
    }

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

    func requeue(_ events: [QueuedAnalyticsEvent]) {
        lock.lock()
        defer { lock.unlock() }

        var queue = events + loadQueue()
        if queue.count > AnalyticsEventContract.maxQueueSize {
            queue = Array(queue.prefix(AnalyticsEventContract.maxQueueSize))
        }
        saveQueue(queue)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return loadQueue().count
    }

    private func loadQueue() -> [QueuedAnalyticsEvent] {
        guard let data = defaults.data(forKey: queueKey) else { return [] }
        return (try? JSONDecoder().decode([QueuedAnalyticsEvent].self, from: data)) ?? []
    }

    private func saveQueue(_ queue: [QueuedAnalyticsEvent]) {
        if queue.isEmpty {
            defaults.removeObject(forKey: queueKey)
        } else if let data = try? JSONEncoder().encode(queue) {
            defaults.set(data, forKey: queueKey)
        }
    }
}
