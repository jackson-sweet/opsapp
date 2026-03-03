//
//  PermissionService.swift
//  OPS
//
//  Fetches the current user's role and permissions from Supabase.
//  Queries: user_roles -> roles -> role_permissions
//

import Foundation
import Supabase

/// Result of fetching a user's permissions from Supabase
struct PermissionPayload {
    let roleId: String
    let roleName: String
    let roleHierarchy: Int
    let permissions: [String: String]
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

    /// Fetch the user's role and all associated permissions from Supabase.
    /// - Parameter userId: The user's Supabase UUID (users.id, NOT Firebase UID)
    @MainActor
    static func fetchPermissions(userId: String) async throws -> PermissionPayload {
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

        // Build permission map
        var permissionMap: [String: String] = [:]
        for row in permissionRows {
            permissionMap[row.permission] = row.scope
        }

        return PermissionPayload(
            roleId: role.id,
            roleName: role.name,
            roleHierarchy: role.hierarchy,
            permissions: permissionMap
        )
    }
}
