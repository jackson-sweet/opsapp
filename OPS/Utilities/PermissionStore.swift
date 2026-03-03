//
//  PermissionStore.swift
//  OPS
//
//  Holds the current user's RBAC permissions in memory and provides
//  a `can()` method for permission checks throughout the app.
//  Persists to Keychain for offline access.
//

import Foundation
import Combine

/// Cached permission blob stored in Keychain
struct CachedPermissions: Codable {
    let permissions: [String: String]
    let roleName: String
    let roleHierarchy: Int
    let roleId: String
    let userId: String
    let fetchedAt: Date
}

class PermissionStore: ObservableObject {
    /// Singleton for access from data model computed properties and ViewModels
    static let shared = PermissionStore()

    // MARK: - Published State

    @Published var permissions: [String: String] = [:]
    @Published var roleName: String?
    @Published var roleHierarchy: Int?
    @Published var roleId: String?
    @Published var initialized: Bool = false

    // MARK: - Private

    private let keychainManager = KeychainManager()
    private var currentUserId: String?

    // MARK: - Permission Checks

    /// Check if user has a permission, optionally at a required scope level.
    /// Default requiredScope is "all" — pass "assigned" or "own" for relaxed checks.
    func can(_ permission: String, requiredScope: String = "all") -> Bool {
        guard let grantedScope = permissions[permission] else { return false }
        return scopeSatisfies(granted: grantedScope, required: requiredScope)
    }

    /// Get the granted scope for a permission (nil if not granted)
    func scope(for permission: String) -> String? {
        return permissions[permission]
    }

    /// Check if the user has "all" scope for a permission (sees everything, not just assigned)
    func hasFullAccess(_ permission: String) -> Bool {
        return permissions[permission] == "all"
    }

    // MARK: - Scope Hierarchy

    /// Scope hierarchy: all > assigned > own
    private func scopeSatisfies(granted: String, required: String) -> Bool {
        if granted == "all" { return true }
        if granted == "assigned" { return required == "assigned" || required == "own" }
        if granted == "own" { return required == "own" }
        return false
    }

    // MARK: - Load from Cache

    /// Load permissions from Keychain cache. Call on app startup for instant availability.
    @discardableResult
    func loadCachedPermissions() -> Bool {
        guard let data = keychainManager.retrievePermissions(),
              let cached = try? JSONDecoder().decode(CachedPermissions.self, from: data) else {
            return false
        }

        self.permissions = cached.permissions
        self.roleName = cached.roleName
        self.roleHierarchy = cached.roleHierarchy
        self.roleId = cached.roleId
        self.currentUserId = cached.userId
        self.initialized = true

        print("[PERMISSIONS] Loaded \(cached.permissions.count) permissions from cache (role: \(cached.roleName), cached at: \(cached.fetchedAt))")
        return true
    }

    /// Check if cached permissions are stale (older than given hours)
    func isCacheStale(hoursThreshold: Double = 8.0) -> Bool {
        guard let data = keychainManager.retrievePermissions(),
              let cached = try? JSONDecoder().decode(CachedPermissions.self, from: data) else {
            return true
        }
        let ageHours = Date().timeIntervalSince(cached.fetchedAt) / 3600
        return ageHours > hoursThreshold
    }

    // MARK: - Save to Cache

    private func saveToCache(userId: String) {
        guard let roleName = roleName,
              let roleHierarchy = roleHierarchy,
              let roleId = roleId else { return }

        let cached = CachedPermissions(
            permissions: permissions,
            roleName: roleName,
            roleHierarchy: roleHierarchy,
            roleId: roleId,
            userId: userId,
            fetchedAt: Date()
        )

        if let data = try? JSONEncoder().encode(cached) {
            keychainManager.storePermissions(data)
            print("[PERMISSIONS] Saved \(permissions.count) permissions to Keychain cache")
        }
    }

    // MARK: - Fetch from Supabase

    /// Fetch fresh permissions from Supabase and update both in-memory and Keychain cache.
    func fetchPermissions(userId: String) async {
        self.currentUserId = userId

        do {
            let payload = try await PermissionService.fetchPermissions(userId: userId)

            await MainActor.run {
                self.permissions = payload.permissions
                self.roleName = payload.roleName
                self.roleHierarchy = payload.roleHierarchy
                self.roleId = payload.roleId
                self.initialized = true
                self.saveToCache(userId: userId)

                print("[PERMISSIONS] Fetched \(payload.permissions.count) permissions from Supabase (role: \(payload.roleName))")
            }
        } catch {
            print("[PERMISSIONS] Failed to fetch permissions from Supabase: \(error)")

            await MainActor.run {
                if !self.initialized {
                    self.loadCachedPermissions()
                }
            }
        }
    }

    // MARK: - Clear

    /// Clear all permissions (call on logout)
    func clearPermissions() {
        permissions = [:]
        roleName = nil
        roleHierarchy = nil
        roleId = nil
        initialized = false
        currentUserId = nil
        keychainManager.deletePermissions()
        print("[PERMISSIONS] Cleared all permissions and cache")
    }
}
