//
//  SuggestedCalendarEventDTOs.swift
//  OPS
//
//  DTOs for the Phase-C "Suggested events" surface (item 63144953).
//  The read/resolve path over agent_memories commitments, exposed to the
//  Firebase-bridged mobile session through two SECURITY DEFINER RPCs:
//    • get_suggested_calendar_events()        → [SuggestedCalendarEventDTO]
//    • resolve_suggested_calendar_event(uuid) → { resolved: Bool }
//
//  The app NEVER depends on the Phase C engine running: an empty array is the
//  normal, healthy state and the surface simply renders nothing.
//

import Foundation

/// One unresolved, upcoming, time-bearing detected commitment returned by the
/// `get_suggested_calendar_events()` RPC. Maps the function's row shape.
struct SuggestedCalendarEventDTO: Codable, Identifiable, Equatable {
    /// agent_memories.id — also the handle passed to the resolve RPC.
    let id: String
    /// The detected commitment text (natural language) — becomes the event title.
    let content: String
    /// When the commitment is due — becomes the event time.
    let dueDate: Date
    /// Related project/client entity, if Phase C linked one.
    let entityId: String?
    /// Detection confidence, 0…1. Not surfaced to the user — kept for ordering/debug.
    let confidence: Double
    /// Resolution timestamp. Always nil within the getter's filter, kept for forward-compat.
    let resolvedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case content
        case dueDate = "due_date"
        case entityId = "entity_id"
        case confidence
        case resolvedAt = "resolved_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        content = try c.decode(String.self, forKey: .content)
        dueDate = try c.decode(Date.self, forKey: .dueDate)
        entityId = try c.decodeIfPresent(String.self, forKey: .entityId)
        resolvedAt = try c.decodeIfPresent(Date.self, forKey: .resolvedAt)
        // Postgres `numeric` can arrive as a JSON number or, for precision, a
        // string. Decode either; a malformed value falls back to neutral so a
        // single odd row never breaks the whole list.
        if let d = try? c.decode(Double.self, forKey: .confidence) {
            confidence = d
        } else if let s = try? c.decode(String.self, forKey: .confidence), let d = Double(s) {
            confidence = d
        } else {
            confidence = 0.5
        }
    }
}

/// Params for `resolve_suggested_calendar_event(p_memory_id uuid)`.
struct ResolveSuggestedCalendarEventParams: Encodable {
    let p_memory_id: String
}
