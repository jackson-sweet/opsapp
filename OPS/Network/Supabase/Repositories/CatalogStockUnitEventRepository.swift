//
//  CatalogStockUnitEventRepository.swift
//  OPS
//
//  Direct read/write access to the append-only `catalog_stock_unit_events`
//  ledger. The table is immutable (no update/delete, no `updated_at`/`deleted_at`
//  column) so the sync cursor keys off `created_at` and there is no tombstone
//  path. The anon "firebase bridge" RLS enforces `company_id =
//  private.get_user_company_id()` and that the referenced stock unit + variant
//  already exist for the company — so callers MUST create the stock unit
//  server-side before emitting events that reference it.
//

import Foundation
import Supabase

final class CatalogStockUnitEventRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    /// Inbound mirror fetch. Keyed off `created_at` (the only timestamp on this
    /// immutable ledger). Row-resilient so a single undecodable event never
    /// blacks out the entity.
    func fetchForSync(since: Date? = nil) async throws -> [CatalogStockUnitEventDTO] {
        try requireSchema()
        var query = client.from("catalog_stock_unit_events")
            .select()
            .eq("company_id", value: companyId)
        if let since {
            query = query.gte("created_at", value: isoString(since))
        }
        return try await query.order("created_at", ascending: true).executeResilient(label: "catalog_stock_unit_events")
    }

    @discardableResult
    func create(_ dto: CreateCatalogStockUnitEventDTO) async throws -> CatalogStockUnitEventDTO {
        try requireSchema()
        return try await client.from("catalog_stock_unit_events")
            .insert(dto).select().single().execute().value
    }

    private func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func requireSchema() throws {
        guard CatalogSchemaCapabilityGate.current.catalogStockUnits else {
            throw CatalogSchemaCapabilityError.unavailable("catalog_stock_unit_events")
        }
    }
}
