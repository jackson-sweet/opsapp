//
//  SupabaseUUID.swift
//  OPS
//
//  Payload guards for Postgres `uuid` columns.
//

import Foundation

enum SupabaseUUID {
    /// Replaces a payload value bound for a Postgres `uuid` column with NULL
    /// when it is a string that cannot parse as a UUID (e.g. a Firebase UID —
    /// bug 0f86b9b0). Postgres rejects the entire PATCH/INSERT with 22P02 on a
    /// malformed uuid, so a single poisoned attribution field would otherwise
    /// wedge the whole queued operation forever. Absent keys, NSNull, and valid
    /// UUIDs pass through untouched. Shared by both outbound project paths
    /// (OutboundProcessor + DataActor) so they cannot drift.
    static func nullingNonUuidValue(forKey key: String, in payload: [String: Any]) -> [String: Any] {
        guard let raw = payload[key], !(raw is NSNull) else { return payload }
        guard let string = raw as? String, UUID(uuidString: string) == nil else { return payload }
        var sanitized = payload
        sanitized[key] = NSNull()
        return sanitized
    }
}
