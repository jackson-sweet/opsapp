//
//  DeckDesignRepository.swift
//  OPS
//
//  Repository for DeckDesign entity operations via Supabase.
//  Table: deck_designs
//

import Foundation
import Supabase

class DeckDesignRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    // MARK: - Fetch All (for InboundProcessor)

    func fetchAll(since: Date? = nil) async throws -> [SupabaseDeckDesignDTO] {
        var query = client
            .from("deck_designs")
            .select()
            .eq("company_id", value: companyId)

        if let since = since {
            query = query.gte("updated_at", value: ISO8601DateFormatter().string(from: since))
        }

        let response: [SupabaseDeckDesignDTO] = try await query
            .order("created_at", ascending: false)
            .execute()
            .value
        return response
    }

    // MARK: - Fetch for Project

    func fetchForProject(_ projectId: String) async throws -> [SupabaseDeckDesignDTO] {
        try await client
            .from("deck_designs")
            .select()
            .eq("company_id", value: companyId)
            .eq("project_id", value: projectId)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    // MARK: - Create

    func create(_ dto: SupabaseDeckDesignDTO) async throws -> SupabaseDeckDesignDTO {
        try await client
            .from("deck_designs")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    // MARK: - Upsert

    func upsert(_ dto: SupabaseDeckDesignDTO) async throws {
        try await client
            .from("deck_designs")
            .upsert(dto)
            .execute()
    }

    // MARK: - Update Fields

    func updateFields(_ id: String, fields: [String: AnyJSON]) async throws {
        var payload = fields
        payload["updated_at"] = .string(isoNow())

        try await client
            .from("deck_designs")
            .update(payload)
            .eq("id", value: id)
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
            .from("deck_designs")
            .update(payload)
            .eq("id", value: id)
            .execute()
    }
}

private func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}
