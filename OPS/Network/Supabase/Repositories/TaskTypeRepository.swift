//
//  TaskTypeRepository.swift
//  OPS
//
//  Repository for TaskType entity operations via Supabase.
//  Table: task_types_v2  (NOT task_types — the v2 table is the live schema)
//
//  Column note: display name column is `display` (not `name`).
//

import Foundation
import Supabase

class TaskTypeRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    // MARK: - Fetch

    func fetchAll(since: Date? = nil) async throws -> [SupabaseTaskTypeDTO] {
        var query = client
            .from("task_types_v2")
            .select()
            .eq("company_id", value: companyId)

        if let since = since {
            query = query.gte("updated_at", value: isoString(since))
        }

        let response: [SupabaseTaskTypeDTO] = try await query
            .order("display_order", ascending: true)
            .execute()
            .value
        return response
    }

    func fetchOne(_ id: String) async throws -> SupabaseTaskTypeDTO {
        try await client
            .from("task_types_v2")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    // MARK: - Upsert

    func upsert(_ dto: SupabaseTaskTypeDTO) async throws {
        try await client
            .from("task_types_v2")
            .upsert(dto)
            .execute()
    }

    // MARK: - Soft Delete

    func softDelete(_ id: String) async throws {
        struct SoftDelete: Codable {
            let deleted_at: String
            let updated_at: String
        }
        let payload = SoftDelete(deleted_at: isoNow(), updated_at: isoNow())
        try await client
            .from("task_types_v2")
            .update(payload)
            .eq("id", value: id)
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
