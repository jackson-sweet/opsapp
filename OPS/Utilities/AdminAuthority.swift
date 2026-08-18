//
//  AdminAuthority.swift
//  OPS
//
//  Client mirror of the server's admin definition.
//
//  Admin status in OPS is an ACCOUNT fact, not a role name. It is decided by
//  three columns and nothing else, and the server decides it in exactly one
//  place — `private.current_user_is_admin()`, which gates 21 RLS policies:
//
//      SELECT EXISTS (
//        SELECT 1
//        FROM public.users u
//        LEFT JOIN public.companies c ON c.id = u.company_id
//        WHERE (u.auth_id = (auth.jwt() ->> 'sub') OR u.firebase_uid = (auth.jwt() ->> 'sub'))
//          AND u.deleted_at IS NULL
//          AND (
//            COALESCE(u.is_company_admin, false)
//            OR u.id::text = c.account_holder_id
//            OR u.id::text = ANY(COALESCE(c.admin_ids, ARRAY[]::text[]))
//          )
//      )
//
//  This type is that boolean, transliterated. It is deliberately pure and
//  deliberately dumb: it holds no policy of its own, reads nothing, and derives
//  nothing. Callers hand it the canonical row values as Postgres returned them
//  (`PermissionService.fetchAdminAuthority`), so the client's answer is computed
//  from the same rows with the same comparisons as the server's — the two cannot
//  disagree.
//
//  Deliberately NOT a role check. The standing rule "never filter by role; only
//  granular permission" governs role NAMES (Admin / Office / Crew strings). This
//  is the account itself.
//

import Foundation

/// The canonical row values `private.current_user_is_admin()` evaluates.
/// Every field is the raw Supabase value — never a locally derived one.
struct AdminAuthorityIdentity: Equatable {

    /// `users.id`, exactly as Postgres returned it (lowercase uuid text). The
    /// server compares `u.id::text` against the company columns, so the value
    /// used here must be the server's, not a locally held id string that may
    /// carry `UUID().uuidString`'s uppercase casing.
    let userId: String

    /// `users.deleted_at IS NOT NULL`. A soft-deleted user is never an admin.
    let isDeleted: Bool

    /// `users.is_company_admin`. NULL reads as false, matching `COALESCE`.
    let isCompanyAdmin: Bool?

    /// `companies.account_holder_id` for the user's company. Stays nil when the
    /// user has no company row — the server's LEFT JOIN leaves it NULL there,
    /// and a NULL comparison is not a match.
    let accountHolderId: String?

    /// `companies.admin_ids`. NULL reads as empty, matching `COALESCE`.
    let adminIds: [String]?
}

enum AdminAuthority {

    /// Whether this identity is a company admin.
    ///
    /// Comparison is exact, byte-for-byte, because the server's is: it compares
    /// `u.id::text` to plain `text` columns. Matching case-insensitively here
    /// would let the client call someone an admin that the server's RLS would
    /// then deny — a broken-affordance failure that is strictly worse than
    /// agreeing with the server.
    static func isAdmin(_ identity: AdminAuthorityIdentity) -> Bool {
        guard !identity.isDeleted else { return false }

        if identity.isCompanyAdmin == true { return true }

        if let accountHolderId = identity.accountHolderId,
           accountHolderId == identity.userId {
            return true
        }

        return (identity.adminIds ?? []).contains(identity.userId)
    }
}
