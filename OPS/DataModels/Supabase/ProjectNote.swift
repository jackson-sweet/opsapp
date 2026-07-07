//
//  ProjectNote.swift
//  OPS
//
//  Per-project message board note — Supabase-backed
//

import SwiftData
import Foundation

@Model
class ProjectNote: Identifiable {
    @Attribute(.unique) var id: String
    var projectId: String
    var companyId: String
    var authorId: String
    var content: String
    var attachmentsJSON: String
    var mentionedUserIdsString: String
    var photoURL: String?
    /// System-event discriminator (live `project_notes.event_kind`). nil for
    /// user notes; `status_change` (web-written), `site_visit` (iOS packet).
    var eventKind: String?
    /// Raw JSON of `project_notes.content_metadata` — structured payload for
    /// system entries (e.g. the site-visit packet summary). nil for user notes.
    var contentMetadataJSON: String?
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
        authorId: String,
        content: String = "",
        photoURL: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.companyId = companyId
        self.authorId = authorId
        self.content = content
        self.attachmentsJSON = "[]"
        self.mentionedUserIdsString = ""
        self.photoURL = photoURL
        self.createdAt = createdAt
    }

    // MARK: - Computed Accessors

    var mentionedUserIds: [String] {
        get {
            guard !mentionedUserIdsString.isEmpty else { return [] }
            return mentionedUserIdsString.components(separatedBy: ",")
        }
        set {
            mentionedUserIdsString = newValue.joined(separator: ",")
        }
    }

    var attachments: [String] {
        get {
            guard !attachmentsJSON.isEmpty, attachmentsJSON != "[]" else { return [] }
            guard let data = attachmentsJSON.data(using: .utf8),
                  let urls = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return urls
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8) else {
                attachmentsJSON = "[]"
                return
            }
            attachmentsJSON = json
        }
    }
}
