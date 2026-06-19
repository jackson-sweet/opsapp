//
//  WizardStateRepository.swift
//  OPS
//
//  Repository for WizardState entity operations via Supabase.
//  Table: wizard_states. User-scoped (no company_id column).
//
//  RLS on wizard_states is scoped to user_id = private.resolve_uid()::text so
//  we only ever filter on the current user — no company_id predicate.
//

import Foundation
import Supabase

class WizardStateRepository {
    private let client: SupabaseClient
    private let userId: String

    init(userId: String) {
        self.client = SupabaseService.shared.client
        self.userId = userId
    }

    // MARK: - Fetch All (for InboundProcessor)

    /// Fetches every wizard_states row for the configured userId.
    /// When `since` is provided, narrows to rows updated at or after that timestamp
    /// (delta sync). Matches the DeckDesignRepository.fetchAll shape.
    func fetchAll(since: Date? = nil) async throws -> [SupabaseWizardStateDTO] {
        var query = client
            .from("wizard_states")
            .select()
            .eq("user_id", value: userId)

        if let since = since {
            query = query.gte("updated_at", value: ISO8601DateFormatter().string(from: since))
        }

        let response: [SupabaseWizardStateDTO] = try await query
            .order("updated_at", ascending: false)
            .execute()
            .value
        return response
    }

    // MARK: - Fetch for User (explicit)

    /// Convenience that accepts a userId directly, ignoring the repo's configured
    /// one. Useful when the caller already holds a user context (e.g., WizardStateManager).
    func fetchForUser(_ userId: String, since: Date? = nil) async throws -> [SupabaseWizardStateDTO] {
        var query = client
            .from("wizard_states")
            .select()
            .eq("user_id", value: userId)

        if let since = since {
            query = query.gte("updated_at", value: ISO8601DateFormatter().string(from: since))
        }

        let response: [SupabaseWizardStateDTO] = try await query
            .order("updated_at", ascending: false)
            .executeResilient(label: "wizard_states")
        return response
    }

    // MARK: - Create

    func create(_ dto: CreateWizardStateDTO) async throws -> SupabaseWizardStateDTO {
        try await client
            .from("wizard_states")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    // MARK: - Upsert

    /// Inserts or replaces the row. Server-side `updated_at` default refreshes on
    /// upsert via the wizard_states trigger. RLS ensures we can only upsert our own rows.
    func upsert(_ dto: SupabaseWizardStateDTO) async throws {
        try await client
            .from("wizard_states")
            .upsert(dto)
            .execute()
    }

    // MARK: - Update Fields

    func updateFields(_ id: String, fields: [String: AnyJSON]) async throws {
        var payload = fields
        payload["updated_at"] = .string(isoNow())

        try await client
            .from("wizard_states")
            .update(payload)
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Delete

    /// Hard delete. `wizard_states` has no `deleted_at` column — rows are removed
    /// outright when the user resets wizard progress. RLS ensures we can only
    /// delete our own rows.
    func delete(id: String) async throws {
        try await client
            .from("wizard_states")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}

private func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}
