//
//  MarkupLayer.swift
//  OPS
//
//  Author-scoped collaborative photo markup. Each author owns ONE layer on a
//  shared `project_photo_annotations` row (layerId == authorId == users.id). The
//  editor composites every other author's overlay PNG as a non-editable base
//  under the current user's PencilKit canvas; each user edits only their own
//  layer. Persisted in `project_photo_annotations.layers` (jsonb) and merged
//  server-side by the `upsert_markup_layer` RPC — NEVER a wholesale update().
//
//  Spec: docs/superpowers/specs/2026-06-23-photo-markup-collab-spec.md
//
//  Wire format: camelCase jsonb keys (match the RPC's `->> 'layerId'` reads and
//  the spec), dates as ISO-8601 strings (SupabaseDate) so the encoding is stable
//  whether it round-trips through our coder OR supabase-swift's RPC encoder.
//

import Foundation

// MARK: - MarkupLayer

struct MarkupLayer: Codable, Equatable, Identifiable {
    /// Stable per-author id. Equals `authorId` and the author's `users.id`. The
    /// RPC enforces a caller may only upsert the layer whose layerId is their own
    /// user id, so peers' layers can never be overwritten by a spoofed id.
    var layerId: String
    var authorId: String
    var authorName: String
    /// S3 URL of this author's transparent overlay PNG. Nil when cleared/offline.
    var overlayUrl: String?
    /// S3 URL of this author's `PKDrawing.dataRepresentation` blob (resume the
    /// editable strokes cross-device). Nil when cleared/offline. NOT inlined as
    /// base64 — that would bloat every get_photo_annotations_since pull.
    var strokeRef: String?
    var visibleDefault: Bool
    var zIndex: Int
    var createdAt: Date
    var updatedAt: Date
    /// Set when the author cleared their own marks. A layer is "active" while nil.
    var clearedAt: Date?

    var id: String { layerId }
    var isCleared: Bool { clearedAt != nil }
    var isActive: Bool { clearedAt == nil }

    init(
        layerId: String,
        authorId: String,
        authorName: String,
        overlayUrl: String?,
        strokeRef: String?,
        visibleDefault: Bool = true,
        zIndex: Int = 0,
        createdAt: Date,
        updatedAt: Date,
        clearedAt: Date? = nil
    ) {
        self.layerId = layerId
        self.authorId = authorId
        self.authorName = authorName
        self.overlayUrl = overlayUrl
        self.strokeRef = strokeRef
        self.visibleDefault = visibleDefault
        self.zIndex = zIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.clearedAt = clearedAt
    }

    enum CodingKeys: String, CodingKey {
        case layerId, authorId, authorName, overlayUrl, strokeRef
        case visibleDefault, zIndex, createdAt, updatedAt, clearedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layerId = try c.decode(String.self, forKey: .layerId)
        // authorId historically may be absent on a hand-built event; fall back to layerId.
        authorId = (try? c.decodeIfPresent(String.self, forKey: .authorId)) ?? layerId
        authorName = (try? c.decodeIfPresent(String.self, forKey: .authorName)) ?? ""
        overlayUrl = try c.decodeIfPresent(String.self, forKey: .overlayUrl)
        strokeRef = try c.decodeIfPresent(String.self, forKey: .strokeRef)
        visibleDefault = (try? c.decodeIfPresent(Bool.self, forKey: .visibleDefault)) ?? true
        zIndex = (try? c.decodeIfPresent(Int.self, forKey: .zIndex)) ?? 0
        createdAt = MarkupCoding.decodeDate(c, .createdAt) ?? Date(timeIntervalSince1970: 0)
        updatedAt = MarkupCoding.decodeDate(c, .updatedAt) ?? createdAt
        clearedAt = MarkupCoding.decodeDate(c, .clearedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(layerId, forKey: .layerId)
        try c.encode(authorId, forKey: .authorId)
        try c.encode(authorName, forKey: .authorName)
        try c.encodeIfPresent(overlayUrl, forKey: .overlayUrl)
        try c.encodeIfPresent(strokeRef, forKey: .strokeRef)
        try c.encode(visibleDefault, forKey: .visibleDefault)
        try c.encode(zIndex, forKey: .zIndex)
        try c.encode(SupabaseDate.format(createdAt), forKey: .createdAt)
        try c.encode(SupabaseDate.format(updatedAt), forKey: .updatedAt)
        // Omit clearedAt when nil so the RPC's `->> 'clearedAt' is null` active
        // check is correct (an absent key reads as SQL NULL).
        if let clearedAt { try c.encode(SupabaseDate.format(clearedAt), forKey: .clearedAt) }
    }
}

// MARK: - MarkupChangeEvent

struct MarkupChangeEvent: Codable, Equatable, Identifiable {
    var eventId: String
    var authorId: String
    var authorName: String
    var action: Action
    var strokeDelta: Int?
    /// Baked BEFORE/AFTER snapshot URLs. DEFERRED (null until snapshots ship).
    var beforeSnapshotUrl: String?
    var afterSnapshotUrl: String?
    var at: Date

    var id: String { eventId }

    enum Action: String, Codable {
        case added, edited, cleared
    }

    init(
        eventId: String = UUID().uuidString,
        authorId: String,
        authorName: String,
        action: Action,
        strokeDelta: Int? = nil,
        beforeSnapshotUrl: String? = nil,
        afterSnapshotUrl: String? = nil,
        at: Date
    ) {
        self.eventId = eventId
        self.authorId = authorId
        self.authorName = authorName
        self.action = action
        self.strokeDelta = strokeDelta
        self.beforeSnapshotUrl = beforeSnapshotUrl
        self.afterSnapshotUrl = afterSnapshotUrl
        self.at = at
    }

    enum CodingKeys: String, CodingKey {
        case eventId, authorId, authorName, action, strokeDelta
        case beforeSnapshotUrl, afterSnapshotUrl, at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventId = try c.decode(String.self, forKey: .eventId)
        authorId = (try? c.decodeIfPresent(String.self, forKey: .authorId)) ?? ""
        authorName = (try? c.decodeIfPresent(String.self, forKey: .authorName)) ?? ""
        action = (try? c.decodeIfPresent(Action.self, forKey: .action)) ?? .edited
        strokeDelta = try c.decodeIfPresent(Int.self, forKey: .strokeDelta)
        beforeSnapshotUrl = try c.decodeIfPresent(String.self, forKey: .beforeSnapshotUrl)
        afterSnapshotUrl = try c.decodeIfPresent(String.self, forKey: .afterSnapshotUrl)
        at = MarkupCoding.decodeDate(c, .at) ?? Date(timeIntervalSince1970: 0)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(eventId, forKey: .eventId)
        try c.encode(authorId, forKey: .authorId)
        try c.encode(authorName, forKey: .authorName)
        try c.encode(action, forKey: .action)
        try c.encodeIfPresent(strokeDelta, forKey: .strokeDelta)
        try c.encodeIfPresent(beforeSnapshotUrl, forKey: .beforeSnapshotUrl)
        try c.encodeIfPresent(afterSnapshotUrl, forKey: .afterSnapshotUrl)
        try c.encode(SupabaseDate.format(at), forKey: .at)
    }
}

// MARK: - Coding helpers

/// Shared plain JSON coder + resilient array decoding for markup jsonb blobs.
/// Dates are encoded/decoded as ISO strings inside the structs themselves, so a
/// plain JSONEncoder/Decoder (no date strategy) is correct here.
enum MarkupCoding {
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    static func decodeDate<K: CodingKey>(_ container: KeyedDecodingContainer<K>, _ key: K) -> Date? {
        // `try?` flattens the already-optional decodeIfPresent result to String?.
        guard let raw = try? container.decodeIfPresent(String.self, forKey: key) else { return nil }
        return SupabaseDate.parse(raw)
    }

    /// Decode an array of markup elements element-by-element, skipping any that
    /// fail to decode. A single malformed layer/event must never nuke the whole
    /// row's markup (lesson: poisoned-cursor whole-batch decode flaw).
    static func decodeArray<T: Decodable>(_ data: Data?) -> [T] {
        guard let data, !data.isEmpty else { return [] }
        if let strict = try? decoder.decode([T].self, from: data) { return strict }
        guard let raw = try? JSONSerialization.jsonObject(with: data), let array = raw as? [Any] else { return [] }
        return array.compactMap { element in
            guard let elementData = try? JSONSerialization.data(withJSONObject: element) else { return nil }
            return try? decoder.decode(T.self, from: elementData)
        }
    }

    static func encodeArray<T: Encodable>(_ values: [T]) -> Data? {
        guard !values.isEmpty else { return nil }
        return try? encoder.encode(values)
    }
}
