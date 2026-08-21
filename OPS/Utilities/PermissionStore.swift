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
    /// Role/override keys observed during the fetch, including explicit revokes.
    /// Nil = legacy cache, so granular compatibility must fail closed.
    let explicitPermissionKeys: [String]?
    /// Whether the account is a company admin. Nil = legacy cache written
    /// before admin authority existed; it reads as false, which fails closed.
    let isAdmin: Bool?
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

    /// Explicit role/override keys, including denied overrides. Required to
    /// keep legacy pipeline.manage from widening a granular assigned scope or
    /// an explicit revoke.
    @Published private(set) var explicitPermissionKeys: Set<String> = []

    /// Whether this account is a company admin — account holder, a member of
    /// `companies.admin_ids`, or carrying `users.is_company_admin`. Resolved by
    /// `AdminAuthority` from the same rows the server's
    /// `private.current_user_is_admin()` reads, so client and server cannot
    /// disagree. An admin holds every permission at scope `all`; feature flags
    /// still sit above it. Not a role name — see `AdminAuthority`.
    @Published private(set) var isAdmin: Bool = false

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
        // Feature flag gate — sits above RBAC, and above admin authority too: a
        // flag is a rollout/entitlement gate on the whole company, not a
        // permission an admin could grant themselves.
        if blockedByFlags.contains(permission) { return false }

        // Company admins hold every permission at scope `all`. Checked ahead of
        // the map, not merely materialized into it, so a permission key that
        // never made it into the client registry still resolves for an admin —
        // exactly as the server's admin policies would allow.
        if isAdmin { return true }

        guard let grantedScope = permissions[permission] else { return false }
        return scopeSatisfies(granted: grantedScope, required: requiredScope)
    }

    /// Get the granted scope for a permission (nil if not granted or flag-blocked)
    func scope(for permission: String) -> String? {
        if blockedByFlags.contains(permission) { return nil }
        if isAdmin { return "all" }
        return permissions[permission]
    }

    /// Check if the user has "all" scope for a permission (sees everything, not just assigned)
    func hasFullAccess(_ permission: String) -> Bool {
        if blockedByFlags.contains(permission) { return false }
        if isAdmin { return true }
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

    /// Canonical row-specific lead policy for view/edit/assign/convert gates.
    /// Feature-flag-blocked permissions are removed and marked explicit so a
    /// legacy manage grant can never resurrect them through compatibility.
    var leadAccessPolicy: LeadAccessPolicy {
        // A company admin's grants come from the account, not the role tables.
        // Materialize them here too: this policy reads the raw map rather than
        // going through `can()`, so without this an admin would inherit
        // whatever the map happened to contain.
        var effectivePermissions = permissions
        if isAdmin {
            for key in LeadAccessPolicy.granularPermissionKeys {
                effectivePermissions[key] = "all"
            }
        }
        let availablePermissions = effectivePermissions.filter {
            !blockedByFlags.contains($0.key)
        }
        return LeadAccessPolicy(
            currentUserId: currentUserId,
            permissions: availablePermissions,
            explicitPermissionKeys: explicitPermissionKeys.union(blockedByFlags)
        )
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

    // MARK: - Project-Edit Gate

    /// Whether `userId` may edit this exact project. `projects.edit = all`
    /// reaches every project; assigned/own reaches only projects whose team
    /// contains that operator. This is the client-side mirror of the
    /// record-scoped server policy and prevents a scoped grant from becoming a
    /// company-wide edit affordance.
    func canEditProject(_ project: Project, userId: String) -> Bool {
        guard let granted = scope(for: "projects.edit") else { return false }
        if granted == "all" { return true }
        let canonicalUserId = userId.lowercased()
        return project.getTeamMemberIds().contains {
            $0.lowercased() == canonicalUserId
        }
    }

    // MARK: - Task-Edit Gates

    /// Whether the current user may edit a task's *fields* (type, description,
    /// title) — `tasks.edit`, scope-aware on the task's assignees exactly like
    /// `canEditSchedule`. Distinct from scheduling: a Crew member may well be
    /// allowed to correct the description of their own job while never being
    /// allowed to move it on the calendar.
    ///
    /// Bug 10b66fce — `ProjectTask.canEdit(user:)` checked `tasks.edit` with a
    /// bare `can()`, which passes for any grant at any scope. An `assigned`
    /// operator therefore read as able to edit every task in the company.
    func canEditTaskFields(assigneeIds: [String]) -> Bool {
        satisfiesAssignedScope(for: "tasks.edit", assigneeIds: assigneeIds)
    }

    /// Whether the current user may change which crew a task is assigned to —
    /// `tasks.assign`. Defined all-only (`PermissionEditorPolicy`), so there is
    /// no assigned-scope reading: you either reassign anyone's work or nobody's.
    var canAssignTaskCrew: Bool {
        hasFullAccess("tasks.assign")
    }

    /// Whether the current user may complete, reopen, or cancel a task —
    /// `tasks.change_status`, scope-aware on the task's assignees. This is the
    /// grant Crew normally holds: act on your own work, don't retype it.
    func canChangeTaskStatus(assigneeIds: [String]) -> Bool {
        satisfiesAssignedScope(for: "tasks.change_status", assigneeIds: assigneeIds)
    }

    /// Shared all/assigned resolution for the per-task gates. Mirrors
    /// `canEditSchedule`: "all" reaches everything, "assigned" reaches only
    /// rows carrying the operator's id, no grant reaches nothing. Ids are
    /// compared case-insensitively — Postgres stores uuids lowercased while
    /// `UUID().uuidString` is uppercase.
    private func satisfiesAssignedScope(for permission: String, assigneeIds: [String]) -> Bool {
        guard let granted = scope(for: permission) else { return false }
        if granted == "all" { return true }
        guard let uid = currentUserId?.lowercased() else { return false }
        return assigneeIds.contains { $0.lowercased() == uid }
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
            self.explicitPermissionKeys = LeadAccessPolicy.granularPermissionKeys
            // No cache means no proof of anything, admin authority included.
            self.isAdmin = false
            return false
        }

        self.permissions = cached.permissions
        self.roleName = cached.roleName
        self.roleHierarchy = cached.roleHierarchy
        self.roleId = cached.roleId
        self.currentUserId = cached.userId
        self.explicitPermissionKeys = cached.explicitPermissionKeys.map(Set.init)
            ?? LeadAccessPolicy.granularPermissionKeys
        // Legacy cache blobs predate admin authority and decode as nil — read
        // as false, which fails closed until the next successful fetch.
        self.isAdmin = cached.isAdmin ?? false
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
            disabledFlags: Array(disabledFlags),
            explicitPermissionKeys: Array(explicitPermissionKeys),
            isAdmin: isAdmin
        )

        if let data = try? JSONEncoder().encode(cached) {
            keychainManager.storePermissions(data)
            print("[PERMISSIONS] Saved \(permissions.count) permissions to Keychain cache (\(blockedByFlags.count) flag-blocked, \(disabledFlags.count) flags disabled)")
        }
    }

    // MARK: - Apply a Resolved Payload

    /// Commit a freshly resolved payload to in-memory state.
    ///
    /// Extracted from `fetchPermissions` so the resolution semantics — above
    /// all the unknown-admin case — are exercised by tests directly instead of
    /// only through the network path. Not actor-isolated, matching the other
    /// state mutators on this store (`loadCachedPermissions`,
    /// `clearPermissions`, `saveToCache`); the production call site is already
    /// inside `MainActor.run`.
    func apply(_ payload: PermissionPayload, userId: String) {
        self.currentUserId = userId
        self.permissions = payload.permissions
        self.roleName = payload.roleName
        self.roleHierarchy = payload.roleHierarchy
        self.roleId = payload.roleId
        self.explicitPermissionKeys = payload.explicitPermissionKeys
        // A probe that could not complete reports nil — "unknown", not "not an
        // admin". Keep the last-known answer rather than demoting a live admin
        // on a network blip; an explicit `false` is authoritative and demotes.
        self.isAdmin = payload.isAdmin ?? self.isAdmin
        self.initialized = true
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

            // A failed feature-flag fetch is "unknown", NOT "all flags off".
            // fetchFlags throws when it can't reach the server — and it's two
            // extra round-trips, so it drops out well before a weak connection
            // fully fails. On a throw we KEEP the last-known-good flag state
            // instead of failing closed, which would otherwise hide DECK /
            // pipeline / estimates / accounting the moment reception wavers —
            // the "tab disappears as if it's live-syncing my permissions" bug.
            let freshFlags: FeatureFlagResult? = try? await flagsFetch

            await MainActor.run {
                // Detect role change to trigger Spotlight re-index with the new scope
                let lastRoleKey = "spotlight.lastIndexedRoleId"
                let previousRoleId = UserDefaults.standard.string(forKey: lastRoleKey)
                let roleChanged = previousRoleId != nil && previousRoleId != payload.roleId

                // Cache-first flag resolution: keep the flags we already trust
                // when the fresh fetch couldn't complete; a fresh result wins.
                let lastKnownFlags = FeatureFlagResult(
                    blockedPermissions: self.blockedByFlags,
                    disabledFlags: self.disabledFlags
                )
                let resolvedFlags = FeatureFlagService.resolve(fresh: freshFlags, lastKnown: lastKnownFlags)
                self.blockedByFlags = resolvedFlags.blockedPermissions
                self.disabledFlags = resolvedFlags.disabledFlags
                if freshFlags == nil {
                    print("[PERMISSIONS] Feature-flag fetch failed — preserving last-known-good flag state (\(resolvedFlags.disabledFlags.count) disabled, \(resolvedFlags.blockedPermissions.count) blocked)")
                }

                self.apply(payload, userId: userId)
                self.saveToCache(userId: userId)
                UserDefaults.standard.set(payload.roleId, forKey: lastRoleKey)

                print("[PERMISSIONS] Fetched \(payload.permissions.count) permissions from Supabase (role: \(payload.roleName), \(resolvedFlags.blockedPermissions.count) flag-blocked, \(resolvedFlags.disabledFlags.count) flags disabled)")

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
                // A transient RBAC-permissions fetch failure must NOT strip
                // already-granted feature flags. The flag fetch
                // (FeatureFlagService.fetchFlags) swallows its own errors, so
                // reaching here means the *permissions* call threw — which says
                // nothing about flag entitlements. Once we have a good in-memory
                // state (initialized), keep the existing blockedByFlags/
                // disabledFlags untouched; only when we have no prior state do we
                // fall back to the cache, which itself fails closed when empty or
                // legacy (see loadCachedPermissions). Previously this branch
                // unconditionally overwrote the flag state with
                // failClosedResult(), so any foreground RBAC blip hid DECK /
                // pipeline / estimates / accounting for entitled users until the
                // next successful fetch — surfacing as "the tab disappears as if
                // it's trying to live-sync my permissions."
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
        isAdmin = false
        explicitPermissionKeys = LeadAccessPolicy.granularPermissionKeys
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

#if DEBUG

// MARK: - Preview / test seam

extension PermissionStore {

    /// The operator identity that assigned-scope policies match rows against.
    ///
    /// Production sets it from the keychain cache or a permissions fetch —
    /// neither of which a preview or a snapshot host runs. Without it an
    /// `assigned` grant filters every row away and an assigned-scope surface
    /// previews empty, which reads as a layout bug rather than the missing
    /// identity it actually is. DEBUG-only; excluded from release builds.
    func setPreviewOperatorId(_ id: String?) {
        currentUserId = id
    }

    /// Force admin authority on or off for a preview or a snapshot host.
    ///
    /// Production resolves this from Supabase (`AdminAuthority`), which neither
    /// a preview nor a snapshot host runs; without it an admin surface previews
    /// as a locked-out account. DEBUG-only; excluded from release builds.
    func setPreviewAdminAuthority(_ isAdmin: Bool) {
        self.isAdmin = isAdmin
    }
}
#endif
