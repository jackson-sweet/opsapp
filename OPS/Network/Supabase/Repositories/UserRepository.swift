//
//  UserRepository.swift
//  OPS
//
//  Repository for User entity operations via Supabase.
//  Table: users
//

import Foundation
import Supabase

class UserRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    // MARK: - Fetch

    func fetchAll(since: Date? = nil) async throws -> [SupabaseUserDTO] {
        var query = client
            .from("users")
            .select()
            .eq("company_id", value: companyId)

        if let since = since {
            query = query.gte("updated_at", value: isoString(since))
        }

        let response: [SupabaseUserDTO] = try await query
            .order("created_at", ascending: false)
            .execute()
            .value
        return response
    }

    func fetchOne(_ id: String) async throws -> SupabaseUserDTO {
        try await client
            .from("users")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    func fetchByEmail(_ email: String) async throws -> SupabaseUserDTO? {
        let response: [SupabaseUserDTO] = try await client
            .from("users")
            .select()
            .eq("email", value: email)
            .limit(1)
            .execute()
            .value
        return response.first
    }

    // MARK: - Upsert

    func upsert(_ dto: SupabaseUserDTO) async throws {
        try await client
            .from("users")
            .upsert(dto)
            .execute()
    }

    // MARK: - Update

    func updateUser(
        userId: String,
        firstName: String?,
        lastName: String?,
        phone: String?
    ) async throws {
        struct UserUpdate: Codable {
            let first_name: String?
            let last_name: String?
            let phone: String?
            let updated_at: String
        }
        let payload = UserUpdate(
            first_name: firstName,
            last_name: lastName,
            phone: phone,
            updated_at: isoNow()
        )
        try await client
            .from("users")
            .update(payload)
            .eq("id", value: userId)
            .execute()
    }

    func updateProfileImageUrl(userId: String, url: String) async throws {
        struct ProfileImageUpdate: Codable {
            let profile_image_url: String
            let updated_at: String
        }
        let payload = ProfileImageUpdate(profile_image_url: url, updated_at: isoNow())
        try await client
            .from("users")
            .update(payload)
            .eq("id", value: userId)
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
            .from("users")
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
