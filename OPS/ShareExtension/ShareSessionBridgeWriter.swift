//
//  ShareSessionBridgeWriter.swift
//  OPS
//
//  App-side writer for the share-extension session bridge. Snapshots the
//  signed-in session — identity, a short-lived Firebase ID token + expiry, the
//  projects.edit permission, and the editable-project list — into the App Group
//  container so the "Add to OPS" extension can operate without Firebase,
//  Supabase, or SwiftData.
//
//  Called on login (after the user + permissions + company are loaded), on every
//  foreground, and cleared on logout.
//

import Foundation
import SwiftData

@MainActor
enum ShareSessionBridgeWriter {

    /// Hard cap on how many projects we publish into the bridge. The picker is a
    /// searchable list; an operator never scrolls past a couple hundred, and the
    /// cache stays small in the shared container.
    private static let maxProjects = 200

    /// Rebuilds and writes the session bridge from the current signed-in state.
    /// If there is no usable session it clears the bridge (the extension then
    /// shows its signed-out state).
    static func refresh(modelContext: ModelContext?, currentUser: User?) async {
        guard
            let userId = UserDefaults.standard.string(forKey: "currentUserId"), !userId.isEmpty,
            let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId"), !companyId.isEmpty
        else {
            ShareSessionBridgeStore.clear()
            return
        }

        // Best-effort fresh token + expiry. An empty token is fine — the
        // extension then queues for the app to upload on next drain rather than
        // presigning itself.
        var idToken = ""
        var tokenExpiresAt = Date()
        if let result = try? await FirebaseAuthService.shared.getIDTokenResult() {
            idToken = result.token
            tokenExpiresAt = result.expiresAt
        }

        // Same gate that guards every project-level write in OPS.
        let canEdit = PermissionStore.shared.can("projects.edit")
        // Full-access roles (scope "all") can attach to any project; scoped roles
        // only to their team-assigned ones.
        let fullAccess = PermissionStore.shared.hasFullAccess("projects.edit")

        let refs = canEdit
            ? editableProjectRefs(modelContext: modelContext, userId: userId, fullAccess: fullAccess)
            : []

        let bridge = ShareSessionBridge(
            userId: userId,
            companyId: companyId,
            idToken: idToken,
            tokenExpiresAt: tokenExpiresAt,
            canEditProjects: canEdit,
            userDisplayName: currentUser?.fullName,
            editableProjects: refs,
            updatedAt: Date()
        )
        ShareSessionBridgeStore.write(bridge)
    }

    /// Clears the bridge on logout and discards any captured-but-unfinalized
    /// share photos, so a different account signing in next can never inherit
    /// the previous user's queued uploads.
    static func clearForLogout() {
        ShareSessionBridgeStore.clear()
        for job in ShareUploadManifestStore.allJobs() {
            ShareUploadManifestStore.remove(id: job.id)
        }
    }

    // MARK: - Project list

    /// Builds the editable-project list for the picker: non-deleted, non-terminal
    /// projects the user may attach photos to, most-recently-touched first.
    private static func editableProjectRefs(
        modelContext: ModelContext?,
        userId: String,
        fullAccess: Bool
    ) -> [ShareProjectRef] {
        guard let ctx = modelContext else { return [] }

        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.deletedAt == nil }
        )
        guard let projects = try? ctx.fetch(descriptor) else { return [] }

        // Filter + sort in memory: the Status enum and team-membership CSV aren't
        // expressible in a #Predicate, and the list is small.
        let candidates = projects.filter { project in
            guard project.status != .closed, project.status != .archived else { return false }
            if fullAccess { return true }
            return project.getTeamMemberIds().contains(userId)
        }

        let sorted = candidates.sorted { lhs, rhs in
            let l = lhs.updatedAt ?? lhs.createdAt ?? .distantPast
            let r = rhs.updatedAt ?? rhs.createdAt ?? .distantPast
            return l > r
        }

        return sorted.prefix(maxProjects).map { project in
            let client = project.effectiveClientName
            return ShareProjectRef(
                id: project.id,
                title: project.title,
                clientName: client.isEmpty ? nil : client
            )
        }
    }
}
