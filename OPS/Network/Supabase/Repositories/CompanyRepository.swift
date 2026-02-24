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

    /// Look up a company by its human-readable company_code (used in the join flow).
    func fetchByCode(_ code: String) async throws -> SupabaseCompanyDTO? {
        let results: [SupabaseCompanyDTO] = try await client
            .from("companies")
            .select()
            .ilike("company_code", value: code)
            .limit(1)
            .execute()
            .value
        return results.first
    }

    // MARK: - Insert

    /// Create a new company row and return the created record.
    func insert(_ payload: NewCompanyPayload) async throws -> SupabaseCompanyDTO {
        try await client
            .from("companies")
            .insert(payload)
            .select()
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

// MARK: - Payloads

/// Payload for inserting a new company into Supabase.
struct NewCompanyPayload: Codable {
    let name: String
    let email: String?
    let phone: String?
    let address: String?
    let company_code: String
    let admin_ids: [String]
    let account_holder_id: String
    let industries: [String]?
    let company_size: String?
    let company_age: String?
    let subscription_status: String
    let subscription_plan: String
    let trial_start_date: String
    let trial_end_date: String
    let max_seats: Int
    let created_at: String
    let updated_at: String
}

// MARK: - Code Generation

/// Generate a short alphanumeric company code (8 chars, uppercase).
func generateCompanyCode() -> String {
    let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // no ambiguous chars (0/O, 1/I)
    return String((0..<8).map { _ in chars.randomElement()! })
}

// MARK: - ISO8601 Helpers

private func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}

private func isoString(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}
