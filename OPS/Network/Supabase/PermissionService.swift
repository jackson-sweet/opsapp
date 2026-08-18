//
//  PermissionService.swift
//  OPS
//
//  Fetches the current user's role and permissions from Supabase.
//  Queries: user_roles -> roles -> role_permissions
//
//  Company admins never take that path. Admin authority is an account fact
//  (`AdminAuthority`), it is resolved first, and it materializes every
//  permission at scope `all` — mirroring ops-web's permissions store, which has
//  always folded admins in this way. Resolving an admin through `user_roles`
//  threw `.noRoleAssigned` for account holders who have no role row, which left
//  every gate in the app closed and locked real customers out entirely.
//

import Foundation
import Supabase

/// Result of fetching a user's permissions from Supabase
struct PermissionPayload {
    let roleId: String
    let roleName: String
    let roleHierarchy: Int
    let permissions: [String: String]
    /// Every role/override key encountered, including explicit revokes. This
    /// lets row policies distinguish a missing legacy-era grant from a modern
    /// explicit denial without letting pipeline.manage widen it.
    let explicitPermissionKeys: Set<String>
    /// Whether the account is a company admin, as the server defines it.
    /// `nil` means the probe could not complete — "unknown", NOT "not an
    /// admin". `PermissionStore` keeps its last-known answer on `nil` rather
    /// than demoting a live admin on a network blip.
    let isAdmin: Bool?
}

/// Supabase response DTOs
private struct UserRoleRow: Decodable {
    let role_id: String
}

private struct RoleRow: Decodable {
    let id: String
    let name: String
    let hierarchy: Int
}

private struct RolePermissionRow: Decodable {
    let permission: String
    let scope: String
}

struct PermissionOverrideFoldRow: Decodable, Equatable {
    let permission: String
    let scope: String?
    let granted: Bool
}

/// The `users` columns `private.current_user_is_admin()` reads.
private struct AdminUserRow: Decodable {
    let id: String
    let company_id: String?
    let is_company_admin: Bool?
    let deleted_at: String?
}

/// The `companies` columns `private.current_user_is_admin()` reads.
private struct AdminCompanyRow: Decodable {
    let account_holder_id: String?
    let admin_ids: [String]?
}

enum PermissionService {

    enum PermissionError: LocalizedError {
        case noRoleAssigned
        case roleNotFound(String)
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .noRoleAssigned:
                return "User has no role assigned in user_roles table"
            case .roleNotFound(let roleId):
                return "Role \(roleId) not found in roles table"
            case .networkError(let error):
                return "Network error fetching permissions: \(error.localizedDescription)"
            }
        }
    }

    /// `roles` preset row for Admin — id and hierarchy verified live against
    /// the `roles` table. Used to label an admin's resolved state; the grants
    /// themselves never come from this role's `role_permissions` rows.
    static let adminPresetRoleId = "00000000-0000-0000-0000-000000000001"
    static let adminPresetRoleHierarchy = 1

    /// Resolve whether this user is a company admin, from the same rows and
    /// with the same comparisons the server uses.
    ///
    /// Reads `users` and (only when it can still change the answer) `companies`,
    /// then hands both to `AdminAuthority` — the single transliteration of
    /// `private.current_user_is_admin()`. Skipping the company read when
    /// `is_company_admin` is already true saves a round-trip and cannot change
    /// the result: the two remaining disjuncts can only widen a `true`.
    ///
    /// Throws on a genuine fetch failure so the caller can treat it as unknown
    /// rather than as a denial.
    @MainActor
    static func fetchAdminAuthority(userId: String) async throws -> Bool {
        let client = SupabaseService.shared.client

        let userRows: [AdminUserRow] = try await client
            .from("users")
            .select("id, company_id, is_company_admin, deleted_at")
            .eq("id", value: userId)
            .execute()
            .value

        guard let user = userRows.first else { return false }

        var company: AdminCompanyRow?
        if user.is_company_admin != true, let companyId = user.company_id {
            let companyRows: [AdminCompanyRow] = try await client
                .from("companies")
                .select("account_holder_id, admin_ids")
                .eq("id", value: companyId)
                .execute()
                .value
            company = companyRows.first
        }

        return AdminAuthority.isAdmin(
            AdminAuthorityIdentity(
                userId: user.id,
                isDeleted: user.deleted_at != nil,
                isCompanyAdmin: user.is_company_admin,
                accountHolderId: company?.account_holder_id,
                adminIds: company?.admin_ids
            )
        )
    }

    /// The grants a company admin holds.
    ///
    /// Materialized from the canonical client registry at scope `all` rather
    /// than resolved through `user_roles` / `role_permissions` /
    /// `user_permission_overrides` — byte-for-byte the shape ops-web builds for
    /// the same accounts. Overrides are not consulted on purpose: the server
    /// refuses to hold any (`private.guard_user_overrides_final_state` raises
    /// `target_is_admin`), because an admin's power comes from the account, not
    /// from rows. `PermissionStore` additionally short-circuits its gates on
    /// admin authority, so a permission key missing from this registry still
    /// resolves for an admin exactly as the server would allow it.
    static func adminPayload() -> PermissionPayload {
        var permissions: [String: String] = [:]
        for definition in PermissionRegistry.all {
            permissions[definition.id] = "all"
        }

        return PermissionPayload(
            roleId: adminPresetRoleId,
            roleName: "Admin",
            roleHierarchy: adminPresetRoleHierarchy,
            permissions: permissions,
            explicitPermissionKeys: Set(permissions.keys),
            isAdmin: true
        )
    }

    /// Fetch the user's role and all associated permissions from Supabase.
    /// - Parameter userId: The user's Supabase UUID (users.id, NOT Firebase UID)
    @MainActor
    static func fetchPermissions(userId: String) async throws -> PermissionPayload {
        // 0. Admin authority comes first. A company admin holds every
        // permission at scope `all` on the server, and frequently has no
        // `user_roles` row at all — the web signup path never writes one — so
        // resolving them through the role path below throws `.noRoleAssigned`
        // and closes every gate in the app.
        //
        // A probe that FAILS is unknown, not negative: it falls through to the
        // role path and reports `isAdmin = nil`, so the store keeps its
        // last-known answer instead of demoting a live admin on a blip. Same
        // posture the feature-flag fetch already takes.
        var isAdmin: Bool?
        do {
            isAdmin = try await fetchAdminAuthority(userId: userId)
        } catch {
            isAdmin = nil
            print("[PERMISSIONS] Admin authority probe failed — resolving through roles, admin status unchanged: \(error)")
        }

        if isAdmin == true {
            print("[PERMISSIONS] Company admin — granting every permission at scope all (account authority, not a role)")
            return adminPayload()
        }

        let client = SupabaseService.shared.client

        // 1. Get user's role_id from user_roles
        let userRoleRows: [UserRoleRow] = try await client
            .from("user_roles")
            .select("role_id")
            .eq("user_id", value: userId)
            .execute()
            .value

        guard let userRole = userRoleRows.first else {
            throw PermissionError.noRoleAssigned
        }

        let roleId = userRole.role_id

        // 2. Get role details from roles
        let roleRows: [RoleRow] = try await client
            .from("roles")
            .select("id, name, hierarchy")
            .eq("id", value: roleId)
            .execute()
            .value

        guard let role = roleRows.first else {
            throw PermissionError.roleNotFound(roleId)
        }

        // 3. Get all permissions for this role from role_permissions
        let permissionRows: [RolePermissionRow] = try await client
            .from("role_permissions")
            .select("permission, scope")
            .eq("role_id", value: roleId)
            .execute()
            .value

        // Build the effective map and separately retain every explicit key.
        var permissionMap: [String: String] = [:]
        var explicitPermissionKeys = Set(permissionRows.map(\.permission))
        for row in permissionRows {
            permissionMap[row.permission] = row.scope
        }

        // 4. Fetch user-level overrides. If this read fails, granular fallback
        // must fail closed: an unseen explicit revoke cannot be distinguished
        // from an old role with no granular rows.
        let overrides: [PermissionOverrideFoldRow]?
        do {
            overrides = try await client
                .from("user_permission_overrides")
                .select("permission, scope, granted")
                .eq("user_id", value: userId)
                .execute()
                .value
        } catch {
            overrides = nil
            explicitPermissionKeys.formUnion(LeadAccessPolicy.granularPermissionKeys)
        }

        let folded = foldOverrides(
            overrides ?? [],
            into: permissionMap,
            explicitPermissionKeys: explicitPermissionKeys
        )
        permissionMap = folded.permissions
        explicitPermissionKeys = folded.explicitPermissionKeys

        return PermissionPayload(
            roleId: role.id,
            roleName: role.name,
            roleHierarchy: role.hierarchy,
            permissions: permissionMap,
            explicitPermissionKeys: explicitPermissionKeys,
            isAdmin: isAdmin
        )
    }

    /// Mirror `should_use_pipeline_manage_compat`: a legacy inheritance row
    /// (`granted=true, scope=NULL`) is not an authoritative granular choice.
    /// Explicit revokes and scoped grants are authoritative.
    static func foldOverrides(
        _ overrides: [PermissionOverrideFoldRow],
        into permissions: [String: String],
        explicitPermissionKeys: Set<String>
    ) -> (permissions: [String: String], explicitPermissionKeys: Set<String>) {
        var permissions = permissions
        var explicitKeys = explicitPermissionKeys

        for override in overrides {
            if !override.granted || override.scope != nil {
                explicitKeys.insert(override.permission)
            }
            if override.granted, let scope = override.scope {
                permissions[override.permission] = scope
            } else if !override.granted {
                permissions.removeValue(forKey: override.permission)
            }
        }
        return (permissions, explicitKeys)
    }
}
