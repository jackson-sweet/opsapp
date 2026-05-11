//
//  RecipientLookupService.swift
//  OPS
//
//  Looks up users in a company who hold a granular permission.
//  Wraps the public.users_with_permission Postgres RPC.
//
//  Use this for notification dispatch and reviewer assignment.
//  NEVER filter recipients by users.role — this RPC respects the full
//  permission system: company-admin escape hatches, role grants, and
//  per-user overrides.
//

import Foundation
import Supabase

enum RecipientLookupService {

    /// Returns user IDs (as lowercase UUID strings, ready for the
    /// `notifications` table's text columns) of every user in the company
    /// who holds `permission` at `requiredScope` or higher.
    ///
    /// - Parameters:
    ///   - companyId: target company UUID string
    ///   - permission: granular permission key (e.g. "expenses.approve")
    ///   - requiredScope: "all", "assigned", or "own". Defaults to "all"
    ///     (only users with full-scope grants). Use "own" for the most
    ///     permissive query — admits any grant level.
    static func usersWithPermission(
        companyId: String,
        permission: String,
        requiredScope: String = "all"
    ) async throws -> [String] {
        let client = SupabaseService.shared.client
        let raw: [String] = try await client
            .rpc("users_with_permission", params: [
                "p_company_id": companyId,
                "p_permission": permission,
                "p_required_scope": requiredScope
            ])
            .execute()
            .value
        return raw.map { $0.lowercased() }
    }
}
