//
//  TaskRepository.swift
//  OPS
//
//  Repository for ProjectTask entity operations via Supabase.
//  Table: project_tasks
//
//  Column note: task_notes (not notes), custom_title (not title), task_color (not color).
//  Scheduling dates are NOT stored on project_tasks — they live on the linked calendar_event.
//

import Foundation
import Supabase

class TaskRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    // MARK: - Fetch

    func fetchAll(since: Date? = nil) async throws -> [SupabaseProjectTaskDTO] {
        var query = client
            .from("project_tasks")
            .select()
            .eq("company_id", value: companyId)

        if let since = since {
            query = query.gte("updated_at", value: isoString(since))
        }

        let response: [SupabaseProjectTaskDTO] = try await query
            .order("display_order", ascending: true)
            .execute()
            .value
        return response
    }

    func fetchForProject(_ projectId: String) async throws -> [SupabaseProjectTaskDTO] {
        let response: [SupabaseProjectTaskDTO] = try await client
            .from("project_tasks")
            .select()
            .eq("project_id", value: projectId)
            .order("display_order", ascending: true)
            .execute()
            .value
        return response
    }

    func fetchOne(_ id: String) async throws -> SupabaseProjectTaskDTO {
        try await client
            .from("project_tasks")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    // MARK: - Upsert

    func upsert(_ dto: SupabaseProjectTaskDTO) async throws {
        try await client
            .from("project_tasks")
            .upsert(dto)
            .execute()
    }

    // MARK: - Update

    func updateStatus(_ taskId: String, status: String) async throws {
        struct StatusUpdate: Codable {
            let status: String
            let updated_at: String
        }
        let payload = StatusUpdate(status: status, updated_at: isoNow())
        try await client
            .from("project_tasks")
            .update(payload)
            .eq("id", value: taskId)
            .execute()
    }

    /// Updates the task_notes column (not `notes` — that column does not exist on project_tasks).
    func updateNotes(_ taskId: String, notes: String) async throws {
        struct NotesUpdate: Codable {
            let task_notes: String
            let updated_at: String
        }
        let payload = NotesUpdate(task_notes: notes, updated_at: isoNow())
        try await client
            .from("project_tasks")
            .update(payload)
            .eq("id", value: taskId)
            .execute()
    }

    // MARK: - Soft Delete

    func softDelete(_ taskId: String) async throws {
        struct SoftDelete: Codable {
            let deleted_at: String
            let updated_at: String
        }
        let payload = SoftDelete(deleted_at: isoNow(), updated_at: isoNow())
        try await client
            .from("project_tasks")
            .update(payload)
            .eq("id", value: taskId)
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
