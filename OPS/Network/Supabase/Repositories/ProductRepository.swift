//
//  ProductRepository.swift
//  OPS
//
//  Repository for the Supabase `products` table. Wire-field bug fixed:
//  reads/writes base_price (mirrored to default_price by Postgres trigger
//  during the ops-web compatibility window) and unit_cost (was incorrectly
//  cost_price in earlier builds).
//

import Foundation
import Supabase

class ProductRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    func fetchAll(includeInactive: Bool = false) async throws -> [ProductDTO] {
        var query = client.from("products").select().eq("company_id", value: companyId)
            .is("deleted_at", value: nil)
        if !includeInactive {
            query = query.eq("is_active", value: true)
        }
        return try await query.order("name", ascending: true).executeResilient(label: "products")
    }

    func create(_ dto: CreateProductDTO) async throws -> ProductDTO {
        try await client.from("products").insert(dto).select().single().execute().value
    }

    func update(_ id: String, fields: UpdateProductDTO) async throws -> ProductDTO {
        try await client.from("products").update(fields).eq("id", value: id).select().single().execute().value
    }

    func deactivate(_ id: String) async throws {
        try await client.from("products").update(["is_active": false]).eq("id", value: id).execute()
    }

    func softDelete(_ id: String) async throws {
        struct SoftDelete: Codable { let deleted_at: String; let updated_at: String }
        let now = ISO8601DateFormatter().string(from: Date())
        try await client.from("products").update(SoftDelete(deleted_at: now, updated_at: now))
            .eq("id", value: id).execute()
    }
}
