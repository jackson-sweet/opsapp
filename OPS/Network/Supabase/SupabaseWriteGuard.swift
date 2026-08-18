//
//  SupabaseWriteGuard.swift
//  OPS
//
//  The safety net under every outbound field update (bug 2e58c85b).
//
//  PostgREST answers a PATCH that matches no row with 200 and an empty body.
//  Nothing failed, so nothing threw, so the outbound queue retired the operation
//  as delivered — and the operator's edit was gone, with no error, no park, no
//  row in PENDING WORK, nothing on the server. A silent write-off.
//
//  The create barrier (`SyncCrossEntityDependency`) removes the common cause by
//  holding a write until its row's create lands. This is the net under it: with
//  the ordering fixed, a PATCH that still matches nothing means the row is
//  genuinely not addressable — deleted server-side, or invisible to this
//  operator under RLS. Both are permanent, so the operation parks with a reason
//  that names what happened instead of vanishing.
//
//  WHY THE COUNT IS FREE. `PostgrestQueryBuilder.update` already defaults to
//  `returning: .representation`, so every one of these calls has always asked
//  the server to return the rows it changed — the response was simply dropped on
//  the floor. Reading it introduces no new permission surface and no new failure
//  mode: whatever RLS lets the app update, it has always been returning. The
//  added `.select("id")` only narrows the response to one column.
//
//  WHY TOMBSTONE WRITES ARE EXEMPT. A PATCH that sets or clears `deleted_at`
//  crosses the visibility line several SELECT policies draw at exactly that
//  column (`user_can_view_task_columns` returns false the moment `deleted_at` is
//  set). A representation filtered by that policy is not evidence the write
//  missed, and parking a delete the user already saw take effect locally would
//  be a lie in the other direction. Deletes are settled by their own paths.
//

import Foundation
import Supabase

enum SupabaseWriteGuard {

    /// Verifies a field update actually reached a row.
    ///
    /// - Parameters:
    ///   - response: The raw PostgREST body of the update (the representation).
    ///   - table: Supabase table name, for the park reason.
    ///   - id: The row id the update addressed, for the park reason.
    ///   - fields: The payload that was sent — read only to spot tombstone writes.
    ///
    /// Throws `SyncError.serverRowMissing` when the server changed no row.
    /// Anything it cannot read as a JSON array is treated as delivered: this
    /// guard exists to stop silent loss, never to invent a failure from an
    /// unfamiliar response shape.
    static func requireAffectedRow(
        response: Data,
        table: String,
        id: String,
        fields: [String: AnyJSON]
    ) throws {
        guard !isTombstoneWrite(fields) else { return }
        guard let rows = try? JSONSerialization.jsonObject(with: response) as? [Any] else {
            return
        }
        guard rows.isEmpty else { return }
        throw SyncError.serverRowMissing(table: table, id: id)
    }

    /// True when the payload writes the `deleted_at` column at all — setting it
    /// (tombstone) or clearing it (restore). Both move the row across the
    /// visibility line the read policies draw there.
    static func isTombstoneWrite(_ fields: [String: AnyJSON]) -> Bool {
        fields.keys.contains("deleted_at")
    }
}
