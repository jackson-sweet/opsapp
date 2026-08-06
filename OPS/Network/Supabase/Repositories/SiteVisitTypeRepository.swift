//
//  SiteVisitTypeRepository.swift
//  OPS
//
//  Tenant-scoped reads for reusable site-visit checklist templates. Writes use
//  the durable generic SyncOperation queue.
//

import Foundation
import Supabase

final class SiteVisitTypeRepository: @unchecked Sendable {
    private let companyId: String
    private let client: SupabaseClient

    init(
        companyId: String,
        client: SupabaseClient = SupabaseService.shared.client
    ) {
        self.companyId = companyId.lowercased()
        self.client = client
    }

    func fetchAll(since: Date? = nil) async throws -> [SiteVisitTypeDTO] {
        var query = client
            .from("site_visit_types")
            .select()
            .eq("company_id", value: companyId)

        if let since {
            query = query.gte(
                "updated_at",
                value: ISO8601DateFormatter().string(from: since)
            )
        }

        return try await query
            .order("sort_order", ascending: true)
            .executeResilient(label: "site_visit_types")
    }

    func upsert(_ dto: SiteVisitTypeDTO) async throws {
        try await client
            .from("site_visit_types")
            .upsert(dto, onConflict: "id")
            .execute()
    }

    func updateFields(_ id: String, fields: [String: AnyJSON]) async throws {
        var payload = fields
        payload["updated_at"] = .string(
            ISO8601DateFormatter().string(from: Date())
        )
        try await client
            .from("site_visit_types")
            .update(payload)
            .eq("id", value: id.lowercased())
            .eq("company_id", value: companyId)
            .execute()
    }

    func softDelete(_ id: String) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try await updateFields(
            id,
            fields: ["deleted_at": .string(now)]
        )
    }
}
