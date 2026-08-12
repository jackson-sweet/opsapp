//
//  ProjectNoteRepository.swift
//  OPS
//
//  Repository for ProjectNote entity operations via Supabase.
//  Table: project_notes
//

import Foundation
import Supabase

/// The read half of the note repository, as the activity feed needs it. Named
/// so the feed's load order — local rows painted first, server merge second —
/// can be exercised against a fetch that has not resolved.
protocol ProjectNoteFetching {
    func fetchForProject(_ projectId: String) async throws -> [ProjectNoteDTO]
}

class ProjectNoteRepository: ProjectNoteFetching {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    // MARK: - Fetch All (for InboundProcessor)

    func fetchAll(since: Date? = nil) async throws -> [ProjectNoteDTO] {
        var query = client
            .from("project_notes")
            .select()
            .eq("company_id", value: companyId)

        if let since = since {
            query = query.gte("updated_at", value: ISO8601DateFormatter().string(from: since))
        }

        let response: [ProjectNoteDTO] = try await query
            .order("created_at", ascending: false)
            .executeResilient(label: "project_notes")
        return response
    }

    // MARK: - Fetch

    func fetchForProject(_ projectId: String) async throws -> [ProjectNoteDTO] {
        try await client
            .from("project_notes")
            .select()
            .eq("company_id", value: companyId)
            .eq("project_id", value: projectId)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    // MARK: - Create

    func create(_ dto: CreateProjectNoteDTO) async throws -> ProjectNoteDTO {
        try await client
            .from("project_notes")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    // MARK: - Update Attachments

    func updateAttachments(_ noteId: String, attachments: [String]) async throws {
        struct AttachmentUpdate: Codable {
            let attachments: [String]
            let updated_at: String
        }
        let payload = AttachmentUpdate(attachments: attachments, updated_at: isoNow())
        try await client
            .from("project_notes")
            .update(payload)
            .eq("id", value: noteId)
            .execute()
    }

    // MARK: - Fetch for Photo

    func fetchForPhoto(_ photoURL: String, projectId: String) async throws -> [ProjectNoteDTO] {
        try await client
            .from("project_notes")
            .select()
            .eq("company_id", value: companyId)
            .eq("project_id", value: projectId)
            .eq("photo_url", value: photoURL)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    // MARK: - Update Content and Mentions

    /// Replaces the note body and authoritative mention list in one guarded
    /// database transaction. The RPC also persists an immutable edit event,
    /// keyed by `mentionEventId`, so a lost response can be replayed safely.
    func updateMentions(
        _ noteId: String,
        content: String,
        mentionedUserIds: [String],
        mentionEventId: String
    ) async throws {
        struct Parameters: Encodable {
            let p_note_id: String
            let p_content: String
            let p_mentioned_user_ids: [String]
            let p_event_id: String
        }

        try await client
            .rpc(
                "update_project_note_mentions",
                params: Parameters(
                    p_note_id: noteId,
                    p_content: content,
                    p_mentioned_user_ids: mentionedUserIds,
                    p_event_id: mentionEventId
                )
            )
            .execute()
    }

    // MARK: - Soft Delete

    func softDelete(_ noteId: String) async throws {
        struct SoftDelete: Codable {
            let deleted_at: String
            let updated_at: String
        }
        let payload = SoftDelete(deleted_at: isoNow(), updated_at: isoNow())
        try await client
            .from("project_notes")
            .update(payload)
            .eq("id", value: noteId)
            .execute()
    }
}

// MARK: - ISO8601 Helpers

private func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}
