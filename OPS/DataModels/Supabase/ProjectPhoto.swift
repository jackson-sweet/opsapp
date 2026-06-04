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
//  deduped by URL. Writes still flow through `ImageSyncManager`; the sync
//  engine treats this entity as read-only.
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
