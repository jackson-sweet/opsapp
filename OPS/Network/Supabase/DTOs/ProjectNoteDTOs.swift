//
//  ProjectNoteDTOs.swift
//  OPS
//
//  Data Transfer Objects for project_notes Supabase table.
//

import Foundation
import Supabase

struct ProjectNoteDTO: Codable, Identifiable {
    let id: String
    let projectId: String
    let companyId: String
    let authorId: String
    let content: String
    let attachments: [String]?
    let mentionedUserIds: [String]?
    let photoURL: String?
    /// System-event discriminator — `status_change` (web), `site_visit` (iOS).
    let eventKind: String?
    /// Structured payload for system entries (jsonb). Decoded loosely so any
    /// shape a client writes survives the round trip.
    let contentMetadata: AnyJSON?
    let createdAt: String
    let updatedAt: String?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case projectId       = "project_id"
        case companyId       = "company_id"
        case authorId        = "author_id"
        case content
        case attachments
        case mentionedUserIds = "mentioned_user_ids"
        case photoURL        = "photo_url"
        case eventKind       = "event_kind"
        case contentMetadata = "content_metadata"
        case createdAt       = "created_at"
        case updatedAt       = "updated_at"
        case deletedAt       = "deleted_at"
    }

    func toModel() -> ProjectNote {
        let note = ProjectNote(
            id: id,
            projectId: projectId,
            companyId: companyId,
            authorId: authorId,
            content: content,
            photoURL: photoURL,
            createdAt: SupabaseDate.parse(createdAt) ?? Date()
        )
        if let attachments = attachments {
            note.attachments = attachments
        }
        if let mentionedUserIds = mentionedUserIds {
            note.mentionedUserIds = mentionedUserIds
        }
        note.eventKind = eventKind
        note.contentMetadataJSON = Self.metadataJSONString(from: contentMetadata)
        if let updatedAt = updatedAt {
            note.updatedAt = SupabaseDate.parse(updatedAt)
        }
        if let deletedAt = deletedAt {
            note.deletedAt = SupabaseDate.parse(deletedAt)
        }
        return note
    }

    /// Serialize the loosely-decoded jsonb back to a raw JSON string for the
    /// SwiftData model. nil for user notes (no metadata) and for SQL null.
    static func metadataJSONString(from metadata: AnyJSON?) -> String? {
        guard let metadata, metadata != .null else { return nil }
        guard let data = try? JSONEncoder().encode(metadata) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct CreateProjectNoteDTO: Codable {
    let projectId: String
    let companyId: String
    let authorId: String
    let content: String
    let mentionedUserIds: [String]
    let attachments: [String]
    let photoURL: String?

    init(projectId: String, companyId: String, authorId: String, content: String, mentionedUserIds: [String], attachments: [String] = [], photoURL: String? = nil) {
        self.projectId = projectId
        self.companyId = companyId
        self.authorId = authorId
        self.content = content
        self.mentionedUserIds = mentionedUserIds
        self.attachments = attachments
        self.photoURL = photoURL
    }

    enum CodingKeys: String, CodingKey {
        case projectId       = "project_id"
        case companyId       = "company_id"
        case authorId        = "author_id"
        case content
        case mentionedUserIds = "mentioned_user_ids"
        case attachments
        case photoURL        = "photo_url"
    }
}
