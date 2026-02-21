//
//  CompanyRepository.swift
//  OPS
//
//  Repository for Company entity operations via Supabase.
//  Table: companies
//
//  Note: No companyId on init — companyId is passed as a method parameter since
//  the company record itself is what is being fetched (not a filtered list).
//

import Foundation
import Supabase

class CompanyRepository {
    private let client: SupabaseClient

    init() {
        self.client = SupabaseService.shared.client
    }

    // MARK: - Fetch

    func fetch(companyId: String) async throws -> SupabaseCompanyDTO {
        try await client
            .from("companies")
            .select()
            .eq("id", value: companyId)
            .single()
            .execute()
            .value
    }

    // MARK: - Update

    /// Applies a freeform set of string-valued field updates to a company record.
    /// Keys must be exact Supabase column names (snake_case).
    /// The `updated_at` field is automatically appended.
    func update(companyId: String, updates: [String: String]) async throws {
        var payload: [String: AnyJSON] = updates.reduce(into: [:]) { result, pair in
            result[pair.key] = .string(pair.value)
        }
        payload["updated_at"] = .string(isoNow())
        try await client
            .from("companies")
            .update(payload)
            .eq("id", value: companyId)
            .execute()
    }

    /// Replaces the seated_employee_ids array for a company.
    func updateSeatedEmployees(companyId: String, userIds: [String]) async throws {
        struct SeatedEmployeesUpdate: Codable {
            let seated_employee_ids: [String]
            let updated_at: String
        }
        let payload = SeatedEmployeesUpdate(
            seated_employee_ids: userIds,
            updated_at: isoNow()
        )
        try await client
            .from("companies")
            .update(payload)
            .eq("id", value: companyId)
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
