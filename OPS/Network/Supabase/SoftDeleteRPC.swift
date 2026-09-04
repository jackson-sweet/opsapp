//
//  SoftDeleteRPC.swift
//  OPS
//
//  Soft-delete and restore both write `deleted_at`, and every table whose read
//  policy judges that column refuses the write through PostgREST.
//
//  Postgres attaches a table's SELECT policies as WITH CHECK options to ANY
//  UPDATE whose target relation requires ACL_SELECT — and `where id = $1`
//  requires it. On `clients`, `projects` and `project_tasks` the RESTRICTIVE
//  SELECT policy (`role_scope_read`) judges the row's own `deleted_at`, so:
//
//    update clients set updated_at = now() where id = $1  -> ok
//    update clients set deleted_at = now() where id = $1  -> 42501
//    update clients set deleted_at = null  where id = $1  -> 0 rows, silently
//
//  Setting the column is refused outright (no client role can do it at all —
//  RETURNING is not the trigger and `Prefer: return=minimal` does not help), and
//  clearing it matches nothing because the tombstoned row is already invisible
//  to the USING clause, which PostgREST answers 200 with an empty body. The
//  first cost a real customer two client deletions on the founder's phone
//  (2026-09-04 17:15 UTC, two `sync_parked` analytics rows); the second made
//  every Trash restore a silent no-op.
//
//  Both directions therefore run through SECURITY DEFINER RPCs owned by the
//  table owner, which re-state authorization explicitly instead of weakening
//  RLS. Bugs db15baf2 (tasks) and 2a55c78f (clients).
//

import Foundation
import Supabase

// MARK: - RPC Parameters

/// Every RPC in this family answers a jsonb verdict — `{ok, deleted|restored,
/// <entity>_id, deleted_at}` — and reports `false` for the verb on an
/// already-settled row, which is how a retried sync op stays idempotent. The
/// callers do not decode it: there is no branch to take on either answer, and a
/// refusal arrives as a thrown PostgrestError, not as `ok: false`.
struct SoftDeleteTaskRPCParams: Encodable { let p_task_id: String }
struct SoftDeleteClientRPCParams: Encodable { let p_client_id: String }
struct SoftDeleteProjectRPCParams: Encodable { let p_project_id: String }

// MARK: - Tombstone Field Split

/// How an outbound `update` payload touches the tombstone column.
///
/// Restore is staged as an `update` carrying `["deleted_at": NSNull()]`
/// (`DataController.restoreTrash`), so the outbound `"delete"` branch never sees
/// it — the `"update"` branch has to recognise it and route it to the RPC.
enum TombstoneIntent: Equatable {
    case none
    case delete
    case restore
}

/// One leg of an outbound `update`, in the order it must be performed.
enum TombstoneUpdateStep: Equatable {
    /// Send these fields through the entity's normal PATCH path.
    case patch([String: AnyJSON])
    /// Call the entity's soft-delete RPC.
    case softDelete
    /// Call the entity's restore RPC.
    case restore
}

/// Splits an outbound update payload into its tombstone intent and the fields
/// that can still travel through PostgREST.
///
/// `deleted_at` can never ride a PATCH on clients / projects / project_tasks —
/// setting it is refused 42501 and clearing it matches zero rows silently — so
/// it is taken out here and settled by an RPC instead.
enum TombstoneFieldSplit {

    /// - Returns: the intent expressed by the payload's `deleted_at` value, and
    ///   the payload with that column (and a now-redundant `updated_at`)
    ///   removed.
    ///
    /// `updated_at` is dropped alongside a tombstone because every RPC in this
    /// family bumps it server-side, and the repositories re-stamp their own
    /// `updated_at` on any PATCH they still send — so keeping it could only
    /// produce a pointless `updated_at`-only PATCH that says nothing.
    static func split(
        _ fields: [String: AnyJSON]
    ) -> (intent: TombstoneIntent, remaining: [String: AnyJSON]) {
        guard let value = fields["deleted_at"] else { return (.none, fields) }

        var remaining = fields
        remaining.removeValue(forKey: "deleted_at")
        remaining.removeValue(forKey: "updated_at")

        // `.null` is how AnyJSONBridge encodes NSNull (AnyJSONBridge.swift:55).
        // A null clears the tombstone; anything else sets one.
        return (value == .null ? .restore : .delete, remaining)
    }

    /// The ordered legs of an outbound `update`.
    ///
    /// ORDER IS LOAD-BEARING, and it is the tombstone that decides it. A
    /// tombstoned row is invisible to the RESTRICTIVE read policy the UPDATE's
    /// USING clause consults, so a PATCH aimed at it matches nothing and
    /// `SupabaseWriteGuard` correctly parks the operation as unaddressable:
    ///
    /// - deleting, sibling fields go FIRST, while the row is still visible;
    /// - restoring, the RPC goes FIRST, to make the row addressable again.
    ///
    /// A payload with no tombstone keeps today's behaviour exactly — one PATCH
    /// of the untouched payload, sent even when it is empty.
    static func steps(for fields: [String: AnyJSON]) -> [TombstoneUpdateStep] {
        let (intent, remaining) = split(fields)
        switch intent {
        case .none:
            return [.patch(remaining)]
        case .delete:
            return remaining.isEmpty ? [.softDelete] : [.patch(remaining), .softDelete]
        case .restore:
            return remaining.isEmpty ? [.restore] : [.restore, .patch(remaining)]
        }
    }
}
