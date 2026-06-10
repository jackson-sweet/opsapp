//
//  PermissionStore.swift
//  OPS
//
//  Holds the current user's RBAC permissions in memory and provides
//  a `can()` method for permission checks throughout the app.
//  Integrates feature flags: permissions blocked by disabled flags
//  are treated as not granted, even if the role has them.
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
    /// Permissions blocked by disabled feature flags. Nil = legacy cache (use fail-closed fallback).
    let blockedByFlags: [String]?
    /// Feature flag slugs that are disabled. Nil = legacy cache (use fail-closed fallback).
    let disabledFlags: [String]?
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

    /// Permissions blocked by disabled feature flags.
    @Published var blockedByFlags: Set<String> = []

    /// Feature flag slugs that are currently disabled for this user.
    @Published var disabledFlags: Set<String> = []

    // MARK: - Private

    private let keychainManager = KeychainManager()
    private var currentUserId: String?

    // MARK: - Permission Checks

    /// Check if user has a permission, optionally at a required scope level.
    /// Returns false if the permission is blocked by a disabled feature flag,
    /// even if the user's role grants it.
    func can(_ permission: String, requiredScope: String = "all") -> Bool {
        // Feature flag gate — sits above RBAC
        if blockedByFlags.contains(permission) { return false }

        guard let grantedScope = permissions[permission] else { return false }
        return scopeSatisfies(granted: grantedScope, required: requiredScope)
    }

    /// Get the granted scope for a permission (nil if not granted or flag-blocked)
    func scope(for permission: String) -> String? {
        if blockedByFlags.contains(permission) { return nil }
        return permissions[permission]
    }

    /// Check if the user has "all" scope for a permission (sees everything, not just assigned)
    func hasFullAccess(_ permission: String) -> Bool {
        if blockedByFlags.contains(permission) { return false }
        return permissions[permission] == "all"
    }

    /// Check if a permission is blocked by a feature flag (for UI messaging)
    func isBlockedByFlag(_ permission: String) -> Bool {
        return blockedByFlags.contains(permission)
    }

    /// Check if a feature flag is enabled for this user.
    /// Use this to gate entire feature groups (e.g., the FAB "Money" section).
    func isFeatureEnabled(_ slug: String) -> Bool {
        return !disabledFlags.contains(slug)
    }

    // MARK: - Scope Hierarchy

    /// Scope hierarchy: all > assigned > own
    private func scopeSatisfies(granted: String, required: String) -> Bool {
        if granted == "all" { return true }
        if granted == "assigned" { return required == "assigned" || required == "own" }
        if granted == "own" { return required == "own" }
        return false
    }

    // MARK: - Schedule-Edit Gate

    /// Whether the current user may mutate the *schedule* (start/end dates,
    /// reschedule, cascade, extend, clear) of an entity with the given assignee
    /// ids. Scheduling is gated on `calendar.edit` across every surface — Crew and
    /// Unassigned (no grant) can never reschedule; they only change status.
    /// Scope-aware:
    ///   - "all"              → may reschedule any entity
    ///   - "own" / "assigned" → only entities the user is assigned to (their id is
    ///                          among the assignee / team_member_ids)
    ///   - no grant / flag-blocked → false
    /// `assigneeIds` are matched case-insensitively (ids are stored lowercased to
    /// match Postgres uuid casing). Per-entity gate — pair with `canEditAnySchedule`
    /// for section/affordance visibility.
    func canEditSchedule(assigneeIds: [String]) -> Bool {
        guard let granted = scope(for: "calendar.edit") else { return false }
        if granted == "all" { return true }
        guard let uid = currentUserId?.lowercased() else { return false }
        return assigneeIds.contains { $0.lowercased() == uid }
    }

    /// True when the user holds *any* `calendar.edit` grant (all / assigned / own).
    /// Use to show or hide schedule-mutation affordances and sections; gate the
    /// actual mutation per-entity with `canEditSchedule(assigneeIds:)`.
    var canEditAnySchedule: Bool {
        scope(for: "calendar.edit") != nil
    }

    // MARK: - Load from Cache

    /// Load permissions from Keychain cache. Call on app startup for instant availability.
    @discardableResult
    func loadCachedPermissions() -> Bool {
        guard let data = keychainManager.retrievePermissions(),
              let cached = try? JSONDecoder().decode(CachedPermissions.self, from: data) else {
            // No cache at all — fail closed on feature flags
            let failClosed = FeatureFlagService.failClosedResult()
            self.blockedByFlags = failClosed.blockedPermissions
            self.disabledFlags = failClosed.disabledFlags
            return false
        }

        self.permissions = cached.permissions
        self.roleName = cached.roleName
        self.roleHierarchy = cached.roleHierarchy
        self.roleId = cached.roleId
        self.currentUserId = cached.userId
        self.initialized = true

        // Restore flag state from cache, or fail closed if legacy cache format
        if let cachedBlocked = cached.blockedByFlags, let cachedDisabled = cached.disabledFlags {
            self.blockedByFlags = Set(cachedBlocked)
            self.disabledFlags = Set(cachedDisabled)
        } else {
            let failClosed = FeatureFlagService.failClosedResult()
            self.blockedByFlags = failClosed.blockedPermissions
            self.disabledFlags = failClosed.disabledFlags
        }

        print("[PERMISSIONS] Loaded \(cached.permissions.count) permissions from cache (role: \(cached.roleName), \(blockedByFlags.count) flag-blocked, \(disabledFlags.count) flags disabled, cached at: \(cached.fetchedAt))")
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
            fetchedAt: Date(),
            blockedByFlags: Array(blockedByFlags),
            disabledFlags: Array(disabledFlags)
        )

        if let data = try? JSONEncoder().encode(cached) {
            keychainManager.storePermissions(data)
            print("[PERMISSIONS] Saved \(permissions.count) permissions to Keychain cache (\(blockedByFlags.count) flag-blocked, \(disabledFlags.count) flags disabled)")
        }
    }

    // MARK: - Fetch from Supabase

    /// Fetch fresh permissions and feature flags from Supabase.
    /// Updates both in-memory state and Keychain cache.
    func fetchPermissions(userId: String) async {
        self.currentUserId = userId

        do {
            // Fetch RBAC permissions and feature flags in parallel
            async let permissionsFetch = PermissionService.fetchPermissions(userId: userId)
            async let flagsFetch = FeatureFlagService.fetchFlags(userId: userId)

            let payload = try await permissionsFetch
            let flagResult = await flagsFetch

            await MainActor.run {
                // Detect role change to trigger Spotlight re-index with the new scope
                let lastRoleKey = "spotlight.lastIndexedRoleId"
                let previousRoleId = UserDefaults.standard.string(forKey: lastRoleKey)
                let roleChanged = previousRoleId != nil && previousRoleId != payload.roleId

                self.permissions = payload.permissions
                self.roleName = payload.roleName
                self.roleHierarchy = payload.roleHierarchy
                self.roleId = payload.roleId
                self.blockedByFlags = flagResult.blockedPermissions
                self.disabledFlags = flagResult.disabledFlags
                self.initialized = true
                self.saveToCache(userId: userId)
                UserDefaults.standard.set(payload.roleId, forKey: lastRoleKey)

                print("[PERMISSIONS] Fetched \(payload.permissions.count) permissions from Supabase (role: \(payload.roleName), \(flagResult.blockedPermissions.count) flag-blocked, \(flagResult.disabledFlags.count) flags disabled)")

                if roleChanged {
                    print("[PERMISSIONS] Role changed from \(previousRoleId ?? "nil") to \(payload.roleId) — requesting Spotlight re-index")
                    NotificationCenter.default.post(
                        name: Notification.Name("SpotlightReindexRequested"),
                        object: nil
                    )
                }
            }
        } catch {
            print("[PERMISSIONS] Failed to fetch permissions from Supabase: \(error)")

            await MainActor.run {
                // Fail closed on feature flags even if permissions fetch fails
                let failClosed = FeatureFlagService.failClosedResult()
                self.blockedByFlags = failClosed.blockedPermissions
                self.disabledFlags = failClosed.disabledFlags

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
        let failClosed = FeatureFlagService.failClosedResult()
        blockedByFlags = failClosed.blockedPermissions
        disabledFlags = failClosed.disabledFlags
        keychainManager.deletePermissions()
        print("[PERMISSIONS] Cleared all permissions and cache")
    }

    // MARK: - Per-Project Access (Bug G9 — mention-grant aware)

    /// True if the current user can VIEW this project. Combines:
    ///  - Feature-flag gate on `projects.view` (no override)
    ///  - `all` scope → always true
    ///  - `assigned` scope → team member OR mention-granted (via MentionAccessIndex)
    ///  - `own` scope or no permission → false
    ///
    /// Use at the record level wherever today's code calls `can("projects.view")`
    /// and holds an actual Project in hand. Global nav gates stay on `can(...)`.
    @MainActor
    func canViewProject(_ project: Project, userId: String) -> Bool {
        if isBlockedByFlag("projects.view") { return false }
        guard let scope = scope(for: "projects.view") else { return false }

        switch scope {
        case "all":
            return true
        case "assigned":
            if project.getTeamMemberIds().contains(userId) { return true }
            return MentionAccessIndex.shared.contains(project.id)
        default:
            return false
        }
    }

    /// True if the user can post a reply note / attach a reply photo on this project.
    /// Mention-only users retain this (Rule 2 of Bug G9).
    @MainActor
    func canReplyToProjectNotes(project: Project, userId: String) -> Bool {
        canViewProject(project, userId: userId)
    }
}
