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

    // MARK: - Fetch

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

    // MARK: - Create / Update orders

    func createOrder(_ dto: CreateCatalogOrderDTO) async throws -> CatalogOrderDTO {
        try await client.from("catalog_orders").insert(dto).select().single().execute().value
    }

    func updateOrder(_ id: String, fields: UpdateCatalogOrderDTO) async throws -> CatalogOrderDTO {
        var fields = fields
        fields.updatedAt = isoString(Date())
        return try await client.from("catalog_orders")
            .update(fields).eq("id", value: id).select().single().execute().value
    }

    func softDeleteOrder(_ id: String) async throws {
        struct SoftDelete: Codable { let deleted_at: String; let updated_at: String }
        let now = isoString(Date())
        try await client.from("catalog_orders")
            .update(SoftDelete(deleted_at: now, updated_at: now))
            .eq("id", value: id).execute()
    }

    // MARK: - Status transitions

    func markSent(_ id: String) async throws -> CatalogOrderDTO {
        struct Update: Codable { let status: String; let sent_at: String; let updated_at: String }
        let now = isoString(Date())
        return try await client.from("catalog_orders")
            .update(Update(status: "sent", sent_at: now, updated_at: now))
            .eq("id", value: id).select().single().execute().value
    }

    func markFulfilled(_ id: String) async throws -> CatalogOrderDTO {
        struct Update: Codable { let status: String; let fulfilled_at: String; let updated_at: String }
        let now = isoString(Date())
        return try await client.from("catalog_orders")
            .update(Update(status: "fulfilled", fulfilled_at: now, updated_at: now))
            .eq("id", value: id).select().single().execute().value
    }

    func markCancelled(_ id: String) async throws -> CatalogOrderDTO {
        struct Update: Codable { let status: String; let cancelled_at: String; let updated_at: String }
        let now = isoString(Date())
        return try await client.from("catalog_orders")
            .update(Update(status: "cancelled", cancelled_at: now, updated_at: now))
            .eq("id", value: id).select().single().execute().value
    }

    // MARK: - Items

    func addItem(orderId: String, dto: CreateCatalogOrderItemDTO) async throws -> CatalogOrderItemDTO {
        // `orderId` is the order this item belongs to; the DTO carries it.
        // Argument is provided for symmetry with other repo methods that
        // namespace by parent id.
        _ = orderId
        return try await client.from("catalog_order_items").insert(dto).select().single().execute().value
    }

    func updateItem(_ itemId: String, fields: UpdateCatalogOrderItemDTO) async throws -> CatalogOrderItemDTO {
        try await client.from("catalog_order_items")
            .update(fields).eq("id", value: itemId).select().single().execute().value
    }

    func removeItem(_ itemId: String) async throws {
        try await client.from("catalog_order_items").delete().eq("id", value: itemId).execute()
    }

    // MARK: - Helpers

    private func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
