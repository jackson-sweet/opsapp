//
//  ProjectRepository.swift
//  OPS
//
//  Repository for Project entity operations via Supabase.
//  Table: projects
//

import Foundation
import Supabase

class ProjectRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    // MARK: - Fetch

    func fetchAll(since: Date? = nil) async throws -> [SupabaseProjectDTO] {
        var query = client
            .from("projects")
            .select()
            .eq("company_id", value: companyId)

        if let since = since {
            query = query.gte("updated_at", value: isoString(since))
        }

        let response: [SupabaseProjectDTO] = try await query
            .order("created_at", ascending: false)
            .execute()
            .value
        return response
    }

    func fetchOne(_ id: String) async throws -> SupabaseProjectDTO {
        try await client
            .from("projects")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    // MARK: - Upsert

    func upsert(_ dto: SupabaseProjectDTO) async throws {
        try await client
            .from("projects")
            .upsert(dto)
            .execute()
    }

    // MARK: - Update

    func updateStatus(_ projectId: String, status: String) async throws {
        struct StatusUpdate: Codable {
            let status: String
            let updated_at: String
        }
        let payload = StatusUpdate(status: status, updated_at: isoNow())
        try await client
            .from("projects")
            .update(payload)
            .eq("id", value: projectId)
            .execute()
    }

    func updateNotes(_ projectId: String, notes: String) async throws {
        struct NotesUpdate: Codable {
            let notes: String
            let updated_at: String
        }
        let payload = NotesUpdate(notes: notes, updated_at: isoNow())
        try await client
            .from("projects")
            .update(payload)
            .eq("id", value: projectId)
            .execute()
    }

    // MARK: - Soft Delete

    func softDelete(_ projectId: String) async throws {
        struct SoftDelete: Codable {
            let deleted_at: String
            let updated_at: String
        }
        let payload = SoftDelete(deleted_at: isoNow(), updated_at: isoNow())
        try await client
            .from("projects")
            .update(payload)
            .eq("id", value: projectId)
            .execute()
    }
}

// MARK: - ISO8601 Helpers

private func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}

private func isoString(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}
