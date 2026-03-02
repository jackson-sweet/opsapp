//
//  ProjectNoteRepository.swift
//  OPS
//
//  Repository for ProjectNote entity operations via Supabase.
//  Table: project_notes
//

import Foundation
import Supabase

class ProjectNoteRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
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

    // MARK: - Update Content

    func updateContent(_ noteId: String, content: String) async throws {
        struct ContentUpdate: Codable {
            let content: String
            let updated_at: String
        }
        let payload = ContentUpdate(content: content, updated_at: isoNow())
        try await client
            .from("project_notes")
            .update(payload)
            .eq("id", value: noteId)
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
