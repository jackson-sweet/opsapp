//
//  RecurringExpenseRepository.swift
//  OPS
//
//  Repository for Recurring Expense operations via Supabase.
//

import Foundation
import Supabase

class RecurringExpenseRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    func fetchAll() async throws -> [RecurringExpenseDTO] {
        try await client
            .from("recurring_expenses")
            .select("*")
            .eq("company_id", value: companyId)
            .is("deleted_at", value: nil)
            .order("next_due_date", ascending: true)
            .execute()
            .value
    }

    func create(_ dto: CreateRecurringExpenseDTO) async throws -> RecurringExpenseDTO {
        try await client
            .from("recurring_expenses")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    func update(_ id: String, fields: UpdateRecurringExpenseDTO) async throws -> RecurringExpenseDTO {
        try await client
            .from("recurring_expenses")
            .update(fields)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    func softDelete(_ id: String) async throws {
        struct SoftDeletePayload: Codable { let deleted_at: String }
        let payload = SoftDeletePayload(deleted_at: ISO8601DateFormatter().string(from: Date()))
        _ = try await client
            .from("recurring_expenses")
            .update(payload)
            .eq("id", value: id)
            .execute()
    }
}
