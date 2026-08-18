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

/// What this device knows about a photo's `uploaded_by`.
///
/// The distinction between "no value" and "a value that cannot match" is the
/// whole point of this type. `project_photos.uploaded_by` is `NOT NULL` TEXT
/// server-side, so any value this device cannot resolve to a user id is still a
/// value the trigger WILL compare — and reject. Collapsing both states into one
/// optional is what offered a delete badge on every server-written `'system'`
/// photo.
enum ProjectPhotoUploaderAttribution: Equatable {
    /// A canonical `public.users.id`, normalized the way the trigger's
    /// `lower()` comparison reads it.
    case known(String)

    /// This device has no uploader recorded — no `project_photos` row for the
    /// URL yet, or a local row whose attribution has not been pulled back.
    case unattributed

    /// A row exists carrying an `uploaded_by` that can never equal a user id:
    /// the server-written `'system'` sentinel, or any other foreign namespace.
    /// `lower(uploaded_by) = lower(v_uid::text)` is unsatisfiable for every
    /// operator, so only the `projects.edit`-at-`all` half of the guard can
    /// authorize the delete.
    case unmatchable

    init(rawUploadedBy rawValue: String?) {
        guard let rawValue else {
            self = .unattributed
            return
        }
        guard let canonicalID = ProjectPhotoUploaderIdentity.canonicalUserID(rawValue) else {
            self = .unmatchable
            return
        }
        self = .known(canonicalID)
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
/// Note what the server does NOT ask for: no `project_photos` UPDATE policy
/// requires a `projects.edit` grant. Company isolation plus the comparison
/// above is the entire rule, so owning the photo is by itself sufficient.
///
/// Kept here, beside the identity normalizer it depends on, so every surface
/// that offers a delete asks the same question and no UI can offer a delete the
/// server will reject.
enum ProjectPhotoDeleteAuthorization {

    /// - Parameters:
    ///   - uploader: what this device knows about the photo's `uploaded_by`.
    ///   - currentUserID: canonical id of the signed-in operator.
    ///   - hasFullProjectEdit: `projects.edit` granted at scope `all`.
    ///   - hasAnyProjectEdit: `projects.edit` granted at any scope. Decides only
    ///     the unattributed case below.
    static func allows(
        uploader: ProjectPhotoUploaderAttribution,
        currentUserID: String?,
        hasFullProjectEdit: Bool,
        hasAnyProjectEdit: Bool
    ) -> Bool {
        if hasFullProjectEdit { return true }

        switch uploader {
        case .known(let uploaderID):
            // The ownership half of the guard, and the whole of it — the server
            // asks for no project-edit grant on your own photo.
            guard let currentUserID else { return false }
            return uploaderID == currentUserID

        case .unmatchable:
            // The trigger raises 42501 here for every non-`all` operator. The
            // badge would be worse than useless: `deleteProjectPhoto` soft-deletes
            // the local row and pushes the legacy CSV removal BEFORE the remote
            // soft-delete, and that remote failure is swallowed as best-effort —
            // so the tile vanishes on this device while the server row lives on.
            return false

        case .unattributed:
            // No synced row. By construction the only gallery URLs in this state
            // are this device's own optimistic appends to the legacy
            // `project_images` CSV — a photo just taken, whose `project_photos`
            // row was inserted remotely but has not been pulled back yet. The
            // server accepts that delete (the operator IS its uploader), so
            // withholding the affordance would strand a crew member with a photo
            // they just took and cannot remove.
            return hasAnyProjectEdit
        }
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
            uploader: ProjectPhotoUploaderAttribution(rawUploadedBy: rawUploader),
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
