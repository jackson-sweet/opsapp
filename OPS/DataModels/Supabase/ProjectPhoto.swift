//
//  ProjectPhoto.swift
//  OPS
//
//  A single project gallery photo — Supabase-backed (`project_photos` table).
//
//  This is the canonical, company-wide photo store. It is synced like
//  `ProjectNote` so every assigned teammate sees the full gallery — not just
//  the uploader. The legacy `projects.project_images` CSV is unreliable
//  (whole-array overwrite, gated by project-edit RLS, not maintained by Web),
//  so it only ever showed the uploader their own optimistic append. The
//  carousel now unions synced `ProjectPhoto` rows with that legacy CSV,
//  deduped by URL. `ImageSyncManager` owns file uploads; an explicit durable
//  create operation owns already-uploaded site-visit handoffs. Inbound sync
//  otherwise treats this entity as server-owned.
//

import SwiftData
import Foundation

@Model
class ProjectPhoto: Identifiable {
    @Attribute(.unique) var id: String
    var projectId: String
    var companyId: String
    var url: String
    var thumbnailURL: String?
    var renderedURL: String?
    var source: String
    var siteVisitId: String?
    var uploadedBy: String
    var caption: String?
    var isClientVisible: Bool
    var takenAt: Date?
    var createdAt: Date
    var updatedAt: Date?
    var deletedAt: Date?

    // Sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false

    init(
        id: String = UUID().uuidString,
        projectId: String,
        companyId: String,
        url: String,
        thumbnailURL: String? = nil,
        renderedURL: String? = nil,
        source: String = "other",
        siteVisitId: String? = nil,
        uploadedBy: String,
        caption: String? = nil,
        isClientVisible: Bool = false,
        takenAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.companyId = companyId
        self.url = url
        self.thumbnailURL = thumbnailURL
        self.renderedURL = renderedURL
        self.source = source
        self.siteVisitId = siteVisitId
        self.uploadedBy = uploadedBy
        self.caption = caption
        self.isClientVisible = isClientVisible
        self.takenAt = takenAt
        self.createdAt = createdAt
    }
}

enum ProjectPhotoUploaderIdentity {
    /// `project_photos.uploaded_by` is the canonical `public.users.id` UUID
    /// serialized as text. Normalize before matching so casing and accidental
    /// transport whitespace cannot break attribution, and reject every other
    /// identity namespace rather than exposing an opaque value in the UI.
    static func canonicalUserID(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uuid = UUID(uuidString: trimmed) else { return nil }
        return uuid.uuidString.lowercased()
    }
}

/// Who may remove a project photo.
///
/// The single client-side statement of the rule the database enforces in
/// `trg_project_photos_00_write_guard`: a `deleted_at` write is allowed when
/// `lower(uploaded_by) = lower(<requesting user>)`, or when the operator holds
/// `projects.edit` at scope `all`. Jackson's 2026-07-29 call — field crews
/// delete their own photos, admins delete any company photo.
///
/// Kept here, beside the identity normalizer it depends on, so every surface
/// that offers a delete asks the same question and no UI can offer a delete the
/// server will reject.
enum ProjectPhotoDeleteAuthorization {

    /// - Parameters:
    ///   - uploaderID: canonical uploader id for the photo, or nil when this
    ///     device has no `project_photos` row for it yet.
    ///   - currentUserID: canonical id of the signed-in operator.
    ///   - hasFullProjectEdit: `projects.edit` granted at scope `all`.
    ///   - hasAnyProjectEdit: `projects.edit` granted at any scope. Decides only
    ///     the unattributed case below.
    static func allows(
        uploaderID: String?,
        currentUserID: String?,
        hasFullProjectEdit: Bool,
        hasAnyProjectEdit: Bool
    ) -> Bool {
        if hasFullProjectEdit { return true }
        guard let uploaderID else {
            // No synced row. By construction the only gallery URLs in this state
            // are this device's own optimistic appends to the legacy
            // `project_images` CSV — a photo just taken, whose `project_photos`
            // row was inserted remotely but has not been pulled back yet. The
            // server accepts that delete (the operator IS its uploader), so
            // withholding the affordance would strand a crew member with a photo
            // they just took and cannot remove.
            return hasAnyProjectEdit
        }
        guard let currentUserID else { return false }
        return uploaderID == currentUserID
    }

    /// Convenience over raw column values — normalizes both sides the way the
    /// trigger's `lower()` comparison does.
    static func allows(
        rawUploader: String?,
        rawCurrentUser: String?,
        hasFullProjectEdit: Bool,
        hasAnyProjectEdit: Bool
    ) -> Bool {
        allows(
            uploaderID: ProjectPhotoUploaderIdentity.canonicalUserID(rawUploader),
            currentUserID: ProjectPhotoUploaderIdentity.canonicalUserID(rawCurrentUser),
            hasFullProjectEdit: hasFullProjectEdit,
            hasAnyProjectEdit: hasAnyProjectEdit
        )
    }
}

extension ProjectPhoto {
    /// Applies server-owned attribution while respecting a pending local field.
    /// Invalid/blank inbound identities never erase a valid local attribution;
    /// the next valid pull or realtime event can still heal a stale row.
    func applyInboundUploader(_ rawValue: String?, isProtected: Bool) {
        guard !isProtected,
              let canonicalID = ProjectPhotoUploaderIdentity.canonicalUserID(rawValue) else {
            return
        }
        uploadedBy = canonicalID
    }
}
