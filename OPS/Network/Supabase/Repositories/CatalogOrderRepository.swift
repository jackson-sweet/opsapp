//
//  CatalogOrderRepository.swift
//  OPS
//

import Foundation
import Supabase

class CatalogOrderRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    func fetchAll(statuses: [String]? = nil) async throws -> [CatalogOrderDTO] {
        var query = client.from("catalog_orders").select().eq("company_id", value: companyId)
            .is("deleted_at", value: nil)
        if let statuses = statuses, !statuses.isEmpty {
            query = query.in("status", values: statuses)
        }
        return try await query.order("created_at", ascending: false).execute().value
    }

    func fetchOrderItems(orderId: String) async throws -> [CatalogOrderItemDTO] {
        try await client.from("catalog_order_items").select().eq("order_id", value: orderId).execute().value
    }

    func createOrder(_ dto: CreateCatalogOrderDTO) async throws -> CatalogOrderDTO {
        try await client.from("catalog_orders").insert(dto).select().single().execute().value
    }

    func addItem(_ dto: CreateCatalogOrderItemDTO) async throws -> CatalogOrderItemDTO {
        try await client.from("catalog_order_items").insert(dto).select().single().execute().value
    }

    func markSent(_ orderId: String) async throws {
        struct Update: Codable { let status: String; let sent_at: String; let updated_at: String }
        let now = ISO8601DateFormatter().string(from: Date())
        try await client.from("catalog_orders")
            .update(Update(status: "sent", sent_at: now, updated_at: now))
            .eq("id", value: orderId).execute()
    }

    func markFulfilled(_ orderId: String) async throws {
        struct Update: Codable { let status: String; let fulfilled_at: String; let updated_at: String }
        let now = ISO8601DateFormatter().string(from: Date())
        try await client.from("catalog_orders")
            .update(Update(status: "fulfilled", fulfilled_at: now, updated_at: now))
            .eq("id", value: orderId).execute()
    }
}
