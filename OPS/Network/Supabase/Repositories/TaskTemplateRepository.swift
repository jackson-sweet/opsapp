//
//  TaskTemplateRepository.swift
//  OPS
//
//  Repository for the Supabase `task_templates` table. Reads / writes are
//  scoped to the company via the parent task_type. RLS does the heavy
//  lifting; we just stay company-correct on the query.
//

import Foundation
import Supabase

class TaskTemplateRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    func fetchAll() async throws -> [TaskTemplateDTO] {
        try await client
            .from("task_templates")
            .select()
            .eq("company_id", value: companyId)
            .is("deleted_at", value: nil)
            .order("display_order", ascending: true)
            .execute()
            .value
    }

    func fetchForTaskType(_ taskTypeId: String) async throws -> [TaskTemplateDTO] {
        try await client
            .from("task_templates")
            .select()
            .eq("company_id", value: companyId)
            .eq("task_type_ref", value: taskTypeId)
            .is("deleted_at", value: nil)
            .order("display_order", ascending: true)
            .execute()
            .value
    }

    func create(_ dto: CreateTaskTemplateDTO) async throws -> TaskTemplateDTO {
        try await client
            .from("task_templates")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    func update(_ id: String, fields: UpdateTaskTemplateDTO) async throws -> TaskTemplateDTO {
        try await client
            .from("task_templates")
            .update(fields)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    func softDelete(_ id: String) async throws {
        struct SoftDelete: Codable { let deleted_at: String; let updated_at: String }
        let now = ISO8601DateFormatter().string(from: Date())
        try await client
            .from("task_templates")
            .update(SoftDelete(deleted_at: now, updated_at: now))
            .eq("id", value: id)
            .execute()
    }
}

/// Adds a convenience fetch on ProductRepository so the TaskTypeSheet can
/// list products linked to the current task type without owning its own
/// network plumbing. Kept here because it's the same wire surface — a
/// thin `eq("task_type_ref")` filter against the `products` table.
extension ProductRepository {
    /// Products whose `task_type_ref` points at the given task type. Used by
    /// the LINKED PRODUCTS section inside `TaskTypeSheet`.
    func fetchForTaskType(_ taskTypeId: String, includeInactive: Bool = true) async throws -> [ProductDTO] {
        var query = SupabaseService.shared.client
            .from("products")
            .select()
            .eq("task_type_ref", value: taskTypeId)
            .is("deleted_at", value: nil)
        if !includeInactive {
            query = query.eq("is_active", value: true)
        }
        return try await query.order("name", ascending: true).execute().value
    }
}
