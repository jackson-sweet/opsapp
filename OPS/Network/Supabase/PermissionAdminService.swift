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
    let isPreset: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, hierarchy
        case isPreset = "is_preset"
    }
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
        let roleName = role.displayName

        if let cached = roleIdCache[roleName] {
            return cached
        }

        let client = SupabaseService.shared.client
        let rows: [AdminRoleRow] = try await client
            .from("roles")
            .select("id, name, hierarchy, is_preset")
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
            .select("id, name, hierarchy, is_preset")
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

    /// Assign a role through the guarded backend boundary. Callers that do not
    /// present the assignment-resolution UI still fail closed if the role
    /// change would strand assigned leads.
    @MainActor
    static func assignUserRole(userId: String, roleId: String) async throws {
        let currentRoleId = try await fetchUserRole(userId: userId)?.role_id
        let payload = try UserRoleMutationRequest(
            expectedRoleId: currentRoleId,
            newRoleId: roleId,
            assignmentResolutions: []
        )
        _ = try await replaceUserRole(userId: userId, request: payload)
    }

    /// Replace the complete editable role permission set through the guarded
    /// backend boundary. The endpoint is responsible for actor authorization,
    /// optimistic permission snapshots, dependency validation, and any lead
    /// responsibility transfer required by a scope reduction.
    @MainActor
    static func replaceRolePermissions(
        roleId: String,
        request payload: RolePermissionMutationRequest
    ) async throws -> RolePermissionMutationSuccess {
        let token = try await FirebaseAuthService.shared.getIDToken()
        let endpoint = AppConfiguration.apiBaseURL
            .appendingPathComponent("api")
            .appendingPathComponent("roles")
            .appendingPathComponent(roleId)
            .appendingPathComponent("permissions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PermissionAdminError.invalidResponse
        }

        if (200..<300).contains(http.statusCode) {
            let result: RolePermissionMutationSuccess
            do {
                result = try JSONDecoder().decode(RolePermissionMutationSuccess.self, from: data)
            } catch {
                throw PermissionAdminError.invalidResponse
            }
            guard result.roleId == roleId,
                  Set(result.permissions.map(\.permission)).count == result.permissions.count,
                  result.permissions == result.permissions.sorted(by: { $0.permission < $1.permission }) else {
                throw PermissionAdminError.invalidResponse
            }
            return result
        }

        if http.statusCode == 409,
           let conflict = try? JSONDecoder().decode(
               RolePermissionMutationConflict.self,
               from: data
           ) {
            throw PermissionAdminError.assignmentResolutionRequired(conflict)
        }
        if http.statusCode == 409,
           let conflict = try? JSONDecoder().decode(
               RolePermissionSnapshotConflict.self,
               from: data
           ),
           conflict.code == "permission_snapshot_mismatch" {
            throw PermissionAdminError.snapshotChanged(conflict.currentPermissions)
        }
        if http.statusCode == 409,
           let conflict = try? JSONDecoder().decode(
               PermissionAssignmentResolutionConflict.self,
               from: data
           ),
           conflict.code == "assignment_resolution_conflict" {
            throw PermissionAdminError.assignmentResolutionChanged
        }

        let envelope = try? JSONDecoder().decode(PermissionAdminErrorEnvelope.self, from: data)
        throw PermissionAdminError.requestFailed(
            envelope?.message ?? "Permission update failed. Try again."
        )
    }

    /// Atomically replace the changed portion of a member's permission
    /// overrides against an exact authoritative snapshot.
    @MainActor
    static func replaceUserPermissionOverrides(
        userId: String,
        request payload: UserPermissionOverrideMutationRequest
    ) async throws -> UserPermissionOverrideMutationSuccess {
        let (data, response) = try await makeGuardedRequest(
            path: ["api", "users", userId, "permission-overrides"],
            body: try JSONEncoder().encode(payload)
        )

        if (200..<300).contains(response.statusCode) {
            let result: UserPermissionOverrideMutationSuccess
            do {
                result = try JSONDecoder().decode(
                    UserPermissionOverrideMutationSuccess.self,
                    from: data
                )
            } catch {
                throw PermissionAdminError.invalidResponse
            }
            guard result.userId == userId,
                  Set(result.overrides.map(\.permission)).count == result.overrides.count,
                  result.overrides.allSatisfy({ !$0.permission.isEmpty }),
                  result.overrides == result.overrides.sorted(by: {
                      $0.permission < $1.permission
                  }) else {
                throw PermissionAdminError.invalidResponse
            }
            return result
        }

        try throwAssignmentConflictIfPresent(data: data, response: response)
        if response.statusCode == 409,
           let conflict = try? JSONDecoder().decode(
               UserPermissionOverrideSnapshotConflict.self,
               from: data
           ),
           conflict.code == "permission_snapshot_mismatch",
           Set(conflict.currentOverrides.map(\.permission)).count
               == conflict.currentOverrides.count,
           conflict.currentOverrides == conflict.currentOverrides.sorted(by: {
               $0.permission < $1.permission
           }) {
            throw PermissionAdminError.userOverrideSnapshotChanged(
                conflict.currentOverrides
            )
        }

        let envelope = try? JSONDecoder().decode(PermissionAdminErrorEnvelope.self, from: data)
        throw PermissionAdminError.requestFailed(
            envelope?.message ?? "Permission update failed. Try again."
        )
    }

    /// Atomically replace a member's role against the authoritative role
    /// snapshot, including any required lead responsibility transfers.
    @MainActor
    static func replaceUserRole(
        userId: String,
        request payload: UserRoleMutationRequest
    ) async throws -> UserRoleMutationSuccess {
        let (data, response) = try await makeGuardedRequest(
            path: ["api", "users", userId, "role"],
            body: try JSONEncoder().encode(payload)
        )

        if (200..<300).contains(response.statusCode) {
            let result: UserRoleMutationSuccess
            do {
                result = try JSONDecoder().decode(UserRoleMutationSuccess.self, from: data)
            } catch {
                throw PermissionAdminError.invalidResponse
            }
            guard result.userId == userId, !result.legacyRole.isEmpty else {
                throw PermissionAdminError.invalidResponse
            }
            return result
        }

        try throwAssignmentConflictIfPresent(data: data, response: response)
        if response.statusCode == 409,
           let conflict = try? JSONDecoder().decode(UserRoleSnapshotConflict.self, from: data),
           conflict.code == "permission_snapshot_mismatch" {
            throw PermissionAdminError.userRoleSnapshotChanged(conflict.currentRoleId)
        }

        let envelope = try? JSONDecoder().decode(PermissionAdminErrorEnvelope.self, from: data)
        throw PermissionAdminError.requestFailed(
            envelope?.message ?? "Role update failed. Try again."
        )
    }

    @MainActor
    private static func makeGuardedRequest(
        path: [String],
        body: Data
    ) async throws -> (Data, HTTPURLResponse) {
        let token = try await FirebaseAuthService.shared.getIDToken()
        let endpoint = path.reduce(AppConfiguration.apiBaseURL) { url, component in
            url.appendingPathComponent(component)
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PermissionAdminError.invalidResponse
        }
        return (data, http)
    }

    private static func throwAssignmentConflictIfPresent(
        data: Data,
        response: HTTPURLResponse
    ) throws {
        guard response.statusCode == 409 else { return }
        if let conflict = try? JSONDecoder().decode(
            RolePermissionMutationConflict.self,
            from: data
        ) {
            throw PermissionAdminError.assignmentResolutionRequired(conflict)
        }
        if let conflict = try? JSONDecoder().decode(
            PermissionAssignmentResolutionConflict.self,
            from: data
        ), conflict.code == "assignment_resolution_conflict" {
            throw PermissionAdminError.assignmentResolutionChanged
        }
    }

    // MARK: - Role CRUD

    /// Create a new custom role.
    @MainActor
    static func createRole(name: String, hierarchy: Int) async throws -> AdminRoleRow {
        let client = SupabaseService.shared.client
        let rows: [AdminRoleRow] = try await client
            .from("roles")
            .insert(["name": name, "hierarchy": "\(hierarchy)"])
            .select("id, name, hierarchy, is_preset")
            .execute()
            .value
        guard let row = rows.first else {
            throw PermissionAdminError.roleNotFound(name)
        }
        print("[PERMISSION_ADMIN] Created role '\(name)' with id \(row.id)")
        return row
    }

    /// Duplicate a role: create new role and copy all permissions from source.
    @MainActor
    static func duplicateRole(sourceRoleId: String, newName: String, hierarchy: Int) async throws -> AdminRoleRow {
        let sourcePerms = try await fetchRolePermissions(roleId: sourceRoleId)
        let snapshot = sourcePerms.map {
            CanonicalRolePermission(permission: $0.permission, scope: $0.scope)
        }
        let request = try RolePermissionMutationRequest(
            expectedPermissions: [],
            desiredLevels: PermissionEditorPolicy.desiredLevels(from: snapshot),
            assignmentResolutions: []
        )
        let newRole = try await createRole(name: newName, hierarchy: hierarchy)
        do {
            _ = try await replaceRolePermissions(roleId: newRole.id, request: request)
        } catch {
            // Do not leave a misleading empty duplicate behind when the
            // guarded replacement rejects the copy.
            try? await deleteRole(roleId: newRole.id)
            throw error
        }
        print("[PERMISSION_ADMIN] Duplicated role to '\(newName)' with \(sourcePerms.count) permissions")
        return newRole
    }

    /// Delete a role and all its permissions.
    @MainActor
    static func deleteRole(roleId: String) async throws {
        let client = SupabaseService.shared.client
        try await client
            .from("role_permissions")
            .delete()
            .eq("role_id", value: roleId)
            .execute()
        try await client
            .from("roles")
            .delete()
            .eq("id", value: roleId)
            .execute()
        print("[PERMISSION_ADMIN] Deleted role \(roleId)")
    }

    /// Rename a role.
    @MainActor
    static func renameRole(roleId: String, name: String) async throws {
        let client = SupabaseService.shared.client
        try await client
            .from("roles")
            .update(["name": name])
            .eq("id", value: roleId)
            .execute()
        print("[PERMISSION_ADMIN] Renamed role \(roleId) to '\(name)'")
    }

    /// Fetch all user IDs assigned to a given role.
    @MainActor
    static func fetchUserIdsForRole(roleId: String) async throws -> [String] {
        let client = SupabaseService.shared.client
        let rows: [AdminUserRoleRow] = try await client
            .from("user_roles")
            .select("user_id, role_id")
            .eq("role_id", value: roleId)
            .execute()
            .value
        return rows.map { $0.user_id }
    }

    // MARK: - Errors

    enum PermissionAdminError: LocalizedError {
        case roleNotFound(String)
        case assignmentResolutionRequired(RolePermissionMutationConflict)
        case assignmentResolutionChanged
        case snapshotChanged([CanonicalRolePermission])
        case userOverrideSnapshotChanged([CanonicalUserPermissionOverride])
        case userRoleSnapshotChanged(String?)
        case invalidResponse
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .roleNotFound(let name):
                return "Role '\(name)' not found in roles table"
            case .assignmentResolutionRequired:
                return "Active leads need a new assignee before this access can be reduced."
            case .assignmentResolutionChanged:
                return "Lead responsibility changed. Review the current assignments and try again."
            case .snapshotChanged:
                return "Permissions changed elsewhere. Refresh and try again."
            case .userOverrideSnapshotChanged:
                return "This member's permissions changed elsewhere. Review the current access and try again."
            case .userRoleSnapshotChanged:
                return "This member's role changed elsewhere. Review the current role and try again."
            case .invalidResponse:
                return "Permission update could not be verified. Refresh and try again."
            case .requestFailed(let message):
                return message
            }
        }
    }
}

private struct PermissionAdminErrorEnvelope: Decodable {
    let error: String?
    let code: String?

    var message: String? { error ?? code }
}
