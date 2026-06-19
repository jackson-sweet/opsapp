//
//  CatalogProductOptionMappingRepository.swift
//  OPS
//

import Foundation
import Supabase

final class CatalogProductOptionMappingRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    func fetchForSync(since: Date? = nil) async throws -> [CatalogProductOptionMappingDTO] {
        try requireSchema()
        var query = client.from("catalog_product_option_mappings")
            .select()
            .eq("company_id", value: companyId)
        if let since {
            query = query.gte("updated_at", value: isoString(since))
        }
        return try await query.order("updated_at", ascending: true).executeResilient(label: "catalog_product_option_mappings")
    }

    func fetchDeletedIds(since: Date) async throws -> [String] {
        try requireSchema()
        struct Row: Codable { let id: String }
        let rows: [Row] = try await client.from("catalog_product_option_mappings")
            .select("id")
            .eq("company_id", value: companyId)
            .not("deleted_at", operator: .is, value: "null")
            .gte("deleted_at", value: isoString(since))
            .execute().value
        return rows.map(\.id)
    }

    func create(_ dto: CreateCatalogProductOptionMappingDTO) async throws -> CatalogProductOptionMappingDTO {
        try requireSchema()
        return try await client.from("catalog_product_option_mappings")
            .insert(dto).select().single().execute().value
    }

    func update(_ id: String, fields: UpdateCatalogProductOptionMappingDTO) async throws -> CatalogProductOptionMappingDTO {
        try requireSchema()
        return try await client.from("catalog_product_option_mappings")
            .update(fields).eq("id", value: id).select().single().execute().value
    }

    func softDelete(_ id: String) async throws {
        try requireSchema()
        struct SoftDelete: Codable { let deleted_at: String; let updated_at: String }
        let now = isoString(Date())
        try await client.from("catalog_product_option_mappings")
            .update(SoftDelete(deleted_at: now, updated_at: now))
            .eq("id", value: id).execute()
    }

    private func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func requireSchema() throws {
        guard CatalogSchemaCapabilityGate.current.catalogProductOptionMappings else {
            throw CatalogSchemaCapabilityError.unavailable("catalog_product_option_mappings")
        }
    }
}
