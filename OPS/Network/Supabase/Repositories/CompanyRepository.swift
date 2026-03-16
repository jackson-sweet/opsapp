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
    ///
    /// Uses the `lookup_company_by_code` SECURITY DEFINER function to bypass RLS,
    /// since new users during onboarding don't have a users row yet and RLS would
    /// block direct table queries.
    func fetchByCode(_ code: String) async throws -> SupabaseCompanyDTO? {
        let results: [SupabaseCompanyDTO] = try await client
            .rpc("lookup_company_by_code", params: ["lookup_code": code])
            .execute()
            .value
        return results.first
    }

    /// Check for pending team invitations matching an email address.
    /// Uses SECURITY DEFINER RPC (bypasses RLS for onboarding users without a company).
    func checkPendingInvites(email: String) async throws -> [PendingInviteDTO] {
        print("[COMPANY_REPO] Checking pending invites for email: \(email)")

        let result: Data = try await client
            .rpc("check_pending_invites", params: ["p_email": email])
            .execute()
            .data

        // Debug: log raw response
        let rawString = String(data: result, encoding: .utf8) ?? "nil"
        print("[COMPANY_REPO] Raw invite response (\(result.count) bytes): \(rawString.prefix(500))")

        let decoder = JSONDecoder()

        // Strategy 1: Direct array decode [PendingInviteDTO]
        if let array = try? decoder.decode([PendingInviteDTO].self, from: result) {
            print("[COMPANY_REPO] Decoded \(array.count) invites (direct array)")
            return array
        }

        // Strategy 2: PostgREST wraps JSONB scalars as [{"function_name": value}]
        // Try unwrapping [{"check_pending_invites": [...]}]
        if let wrapped = try? JSONSerialization.jsonObject(with: result) as? [[String: Any]],
           let firstRow = wrapped.first,
           let innerValue = firstRow["check_pending_invites"] ?? firstRow.values.first,
           let innerData = try? JSONSerialization.data(withJSONObject: innerValue) {
            if let array = try? decoder.decode([PendingInviteDTO].self, from: innerData) {
                print("[COMPANY_REPO] Decoded \(array.count) invites (unwrapped from PostgREST wrapper)")
                return array
            }
        }

        // Strategy 3: Single wrapped value [[{...}]]
        if let outerArray = try? JSONSerialization.jsonObject(with: result) as? [Any],
           let innerArray = outerArray.first,
           let innerData = try? JSONSerialization.data(withJSONObject: innerArray) {
            if let array = try? decoder.decode([PendingInviteDTO].self, from: innerData) {
                print("[COMPANY_REPO] Decoded \(array.count) invites (double-wrapped)")
                return array
            }
        }

        print("[COMPANY_REPO] Failed to decode invites from response")
        return []
    }

    /// Fetch branded company details for the onboarding confirmation screen.
    /// Uses SECURITY DEFINER RPC (bypasses RLS for onboarding users without a company).
    func fetchJoinDetails(code: String) async throws -> CompanyJoinDetailsDTO? {
        let result: Data = try await client
            .rpc("get_company_join_details", params: ["p_code": code])
            .execute()
            .data

        let decoder = JSONDecoder()
        if let single = try? decoder.decode(CompanyJoinDetailsDTO.self, from: result) {
            return single
        }
        if let array = try? decoder.decode([CompanyJoinDetailsDTO].self, from: result),
           let first = array.first {
            return first
        }
        return nil
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

    /// Generic field update accepting AnyJSON values directly.
    func updateFields(companyId: String, fields: [String: AnyJSON]) async throws {
        var payload = fields
        payload["updated_at"] = .string(isoNow())
        try await client
            .from("companies")
            .update(payload)
            .eq("id", value: companyId)
            .execute()
    }

    /// Soft-delete a company by setting deleted_at.
    func softDelete(companyId: String) async throws {
        struct SoftDelete: Codable {
            let deleted_at: String
            let updated_at: String
        }
        let payload = SoftDelete(deleted_at: isoNow(), updated_at: isoNow())
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
    let seated_employee_ids: [String]
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
