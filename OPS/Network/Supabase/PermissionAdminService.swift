//
//  PermissionAdminService.swift
//  OPS
//
//  Admin CRUD for the RBAC tables: roles, role_permissions, user_roles, user_permission_overrides.
//  All methods use SupabaseService.shared.client.
//

import Foundation
import Supabase

// MARK: - DTOs

struct AdminRoleRow: Codable, Identifiable {
    let id: String
    let name: String
    let hierarchy: Int
}

struct AdminRolePermissionRow: Codable, Identifiable {
    var id: String { "\(role_id)_\(permission)" }
    let role_id: String
    let permission: String
    let scope: String
}

struct AdminUserRoleRow: Codable {
    let user_id: String
    let role_id: String
}

struct UserPermissionOverrideRow: Codable, Identifiable {
    let id: String?
    let user_id: String
    let company_id: String
    let permission: String
    let scope: String?
    let granted: Bool
}

// MARK: - Service

enum PermissionAdminService {

    // MARK: - Role ID Cache

    private static var roleIdCache: [String: String] = [:]

    /// Resolve a UserRole enum to its UUID in the `roles` table.
    @MainActor
    static func resolveRoleId(for role: UserRole) async throws -> String {
        let roleName: String
        switch role {
        case .fieldCrew: roleName = "field_crew"
        case .officeCrew: roleName = "office_crew"
        case .admin: roleName = "admin"
        }

        if let cached = roleIdCache[roleName] {
            return cached
        }

        let client = SupabaseService.shared.client
        let rows: [AdminRoleRow] = try await client
            .from("roles")
            .select("id, name, hierarchy")
            .eq("name", value: roleName)
            .execute()
            .value

        guard let row = rows.first else {
            throw PermissionAdminError.roleNotFound(roleName)
        }

        roleIdCache[roleName] = row.id
        return row.id
    }

    // MARK: - Read Methods

    /// Fetch all roles from the `roles` table.
    @MainActor
    static func fetchAllRoles() async throws -> [AdminRoleRow] {
        let client = SupabaseService.shared.client
        let rows: [AdminRoleRow] = try await client
            .from("roles")
            .select("id, name, hierarchy")
            .order("hierarchy", ascending: true)
            .execute()
            .value
        return rows
    }

    /// Fetch all permissions for a given role.
    @MainActor
    static func fetchRolePermissions(roleId: String) async throws -> [AdminRolePermissionRow] {
        let client = SupabaseService.shared.client
        let rows: [AdminRolePermissionRow] = try await client
            .from("role_permissions")
            .select("role_id, permission, scope")
            .eq("role_id", value: roleId)
            .execute()
            .value
        return rows
    }

    /// Fetch a user's role assignment from `user_roles`.
    @MainActor
    static func fetchUserRole(userId: String) async throws -> AdminUserRoleRow? {
        let client = SupabaseService.shared.client
        let rows: [AdminUserRoleRow] = try await client
            .from("user_roles")
            .select("user_id, role_id")
            .eq("user_id", value: userId)
            .execute()
            .value
        return rows.first
    }

    /// Fetch all permission overrides for a user.
    @MainActor
    static func fetchUserOverrides(userId: String) async throws -> [UserPermissionOverrideRow] {
        let client = SupabaseService.shared.client
        let rows: [UserPermissionOverrideRow] = try await client
            .from("user_permission_overrides")
            .select("id, user_id, company_id, permission, scope, granted")
            .eq("user_id", value: userId)
            .execute()
            .value
        return rows
    }

    // MARK: - Write Methods

    /// Assign a role to a user (upsert into `user_roles`).
    @MainActor
    static func assignUserRole(userId: String, roleId: String) async throws {
        let client = SupabaseService.shared.client
        try await client
            .from("user_roles")
            .upsert([
                "user_id": userId,
                "role_id": roleId
            ], onConflict: "user_id")
            .execute()

        print("[PERMISSION_ADMIN] Assigned role \(roleId) to user \(userId)")
    }

    /// Set (upsert) a role permission.
    @MainActor
    static func setRolePermission(roleId: String, permission: String, scope: String) async throws {
        let client = SupabaseService.shared.client
        try await client
            .from("role_permissions")
            .upsert([
                "role_id": roleId,
                "permission": permission,
                "scope": scope
            ], onConflict: "role_id,permission")
            .execute()

        print("[PERMISSION_ADMIN] Set role permission: \(permission) = \(scope) for role \(roleId)")
    }

    /// Remove a role permission.
    @MainActor
    static func removeRolePermission(roleId: String, permission: String) async throws {
        let client = SupabaseService.shared.client
        try await client
            .from("role_permissions")
            .delete()
            .eq("role_id", value: roleId)
            .eq("permission", value: permission)
            .execute()

        print("[PERMISSION_ADMIN] Removed role permission: \(permission) for role \(roleId)")
    }

    /// Set (upsert) a user-level permission override.
    @MainActor
    static func setUserOverride(userId: String, companyId: String, permission: String, scope: String?, granted: Bool) async throws {
        let client = SupabaseService.shared.client
        var record: [String: String] = [
            "user_id": userId,
            "company_id": companyId,
            "permission": permission,
            "granted": granted ? "true" : "false"
        ]
        if let scope = scope {
            record["scope"] = scope
        }

        try await client
            .from("user_permission_overrides")
            .upsert(record, onConflict: "user_id,permission")
            .execute()

        print("[PERMISSION_ADMIN] Set user override: \(permission) granted=\(granted) for user \(userId)")
    }

    /// Remove a user-level permission override.
    @MainActor
    static func removeUserOverride(userId: String, permission: String) async throws {
        let client = SupabaseService.shared.client
        try await client
            .from("user_permission_overrides")
            .delete()
            .eq("user_id", value: userId)
            .eq("permission", value: permission)
            .execute()

        print("[PERMISSION_ADMIN] Removed user override: \(permission) for user \(userId)")
    }

    // MARK: - Errors

    enum PermissionAdminError: LocalizedError {
        case roleNotFound(String)

        var errorDescription: String? {
            switch self {
            case .roleNotFound(let name):
                return "Role '\(name)' not found in roles table"
            }
        }
    }
}
