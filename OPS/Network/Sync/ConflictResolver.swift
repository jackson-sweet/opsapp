//
//  ConflictResolver.swift
//  OPS
//
//  Field-level merge for sync conflicts.
//  Compares local changedFields vs server updated_at to decide which fields win.
//

import Foundation

struct ConflictResolver {

    /// Merge local changes with server version using field-level strategy.
    /// Fields the user actually modified locally take priority when:
    ///   1. Server hasn't changed since local edit (local wins)
    ///   2. Server changed but NOT the same field (local wins)
    ///   3. Both changed same field -> last-write-wins (compare timestamps)
    static func merge(
        localPayload: [String: Any],
        serverPayload: [String: Any],
        changedFields: [String],
        serverUpdatedAt: Date?,
        localChangedAt: Date
    ) -> [String: Any] {
        var merged = serverPayload

        for field in changedFields {
            guard let localValue = localPayload[field] else { continue }

            if let serverTime = serverUpdatedAt, localChangedAt > serverTime {
                // Server hasn't been updated since our change — local wins
                merged[field] = localValue
            } else if serverPayload[field] == nil {
                // Server doesn't have this field — local wins
                merged[field] = localValue
            } else if !areEqual(localPayload[field], serverPayload[field]) {
                // Both changed same field and server is newer — server wins
                // (localChangedAt <= serverTime because the first branch caught the > case)
            } else {
                // Server didn't change this field — local wins
                merged[field] = localValue
            }
        }

        return merged
    }

    private static func areEqual(_ a: Any?, _ b: Any?) -> Bool {
        if a == nil && b == nil { return true }
        guard let a = a, let b = b else { return false }

        switch (a, b) {
        case (let a as String, let b as String): return a == b
        case (let a as Int, let b as Int): return a == b
        case (let a as Double, let b as Double): return a == b
        case (let a as Bool, let b as Bool): return a == b
        default: return false
        }
    }
}
