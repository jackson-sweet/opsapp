import Foundation

/// Small Foundation-only JSON value so saved commands have exactly the same
/// representation on disk, on replay, and in a conflict review.
enum SiteVisitWriteJSON: Codable, Equatable, Sendable {
    case object([String: Self]), array([Self]), string(String), number(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([String: Self].self) { self = .object(v) }
        else { self = .array(try c.decode([Self].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    subscript(_ key: String) -> Self? {
        guard case .object(let v) = self else { return nil }; return v[key]
    }
    var string: String? { guard case .string(let v) = self else { return nil }; return v }
    var revision: Int64? {
        guard case .number(let v) = self, v >= 0, v <= 9_007_199_254_740_991, v.rounded() == v else { return nil }
        return Int64(v)
    }
    /// PostgreSQL may spell the same instant with +00:00 or a different
    /// fractional precision. All other requested values remain exact.
    func matchesRequested(_ requested: Self) -> Bool {
        guard case .object(let values) = requested else { return self == requested }
        return values.allSatisfy { key, value in
            if key == "deleted_at", let lhs = self[key]?.string, let rhs = value.string {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let a = formatter.date(from: lhs)
                let b = formatter.date(from: rhs)
                formatter.formatOptions = [.withInternetDateTime]
                guard let a = a ?? formatter.date(from: lhs), let b = b ?? formatter.date(from: rhs) else { return false }
                return abs(a.timeIntervalSince(b)) < 0.000_001
            }
            if key == "answer_value", case .object(var expected) = value,
               case .object(var actual) = self[key] {
                if expected["artifactIds"] == .array([]) { expected.removeValue(forKey: "artifactIds") }
                if actual["artifactIds"] == .array([]) { actual.removeValue(forKey: "artifactIds") }
                return expected == actual
            }
            return self[key] == value
        }
    }
    static func encode<T: Encodable>(_ value: T) throws -> Self {
        try JSONDecoder().decode(Self.self, from: JSONEncoder().encode(value))
    }
}

struct SiteVisitWriteCommand: Codable, Equatable, Sendable {
    static let revision = "site-visit-writes:2026-09-10.v1"
    var `protocol`: String = Self.revision
    let companyId: String
    let entity: String
    var rows: [Row]

    struct Row: Codable, Equatable, Sendable {
        let id: String
        var baseRevision: Int64
        var before: SiteVisitWriteJSON
        let values: SiteVisitWriteJSON
        enum CodingKeys: String, CodingKey { case id, before, values; case baseRevision = "base_revision" }
    }
    enum CodingKeys: String, CodingKey { case `protocol`, entity, rows; case companyId = "company_id" }

    /// Only the acknowledgement of the exact queued predecessor can advance an
    /// unattempted descendant. An inbound pull or ordinary Retry cannot do so.
    mutating func acknowledgePredecessor(_ receipt: SiteVisitWriteReceipt) {
        guard receipt.outcome == "saved", receipt.entity == entity else { return }
        for index in rows.indices {
            guard let saved = receipt.rows.first(where: { $0["id"]?.string == rows[index].id }),
                  saved["company_id"]?.string == companyId,
                  let revision = saved["write_revision"]?.revision else { continue }
            rows[index].baseRevision = revision
            rows[index].before = saved
        }
    }
}

struct SiteVisitWriteReceipt: Codable, Equatable, Sendable {
    let commandId: UUID
    let entity: String
    let outcome: String
    let reason: String?
    let rows: [SiteVisitWriteJSON]
    enum CodingKeys: String, CodingKey { case entity, outcome, reason, rows; case commandId = "command_id" }
}

struct SiteVisitWriteState: Codable, Equatable, Sendable {
    var revision: Int64 = 0
    var baseRevision: Int64?
    var baseRow: SiteVisitWriteJSON?
    var remoteRow: SiteVisitWriteJSON?

    mutating func begin(_ values: SiteVisitWriteJSON) {
        guard baseRevision == nil else { return }
        baseRevision = revision
        baseRow = values
    }
    mutating func accept(_ row: SiteVisitWriteJSON) {
        revision = row["write_revision"]?.revision ?? 0
        baseRevision = nil; baseRow = nil; remoteRow = nil
    }
}

enum SiteVisitWriteError: Error, LocalizedError {
    case conflict, invalidReceipt, legacyPayload
    var errorDescription: String? {
        switch self {
        case .conflict: return "This form changed on another device. Both versions are saved. Review it in Pending Work."
        case .invalidReceipt: return "The form save could not be verified. Retry the same saved work."
        case .legacyPayload: return "Review this older saved form in Pending Work before sending it."
        }
    }
}

struct SiteVisitWriteResolution: Codable, Equatable, Sendable {
    let id: UUID
    let choice: String
    let current: [SiteVisitWriteJSON]
}
