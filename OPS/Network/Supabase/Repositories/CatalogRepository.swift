//
//  CatalogRepository.swift
//  OPS
//
//  CRUD + sync helpers for catalog_* tables.
//

import Foundation
import Supabase

class CatalogRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    // MARK: - Categories

    func fetchCategoriesForSync(since: Date? = nil) async throws -> [CatalogCategoryDTO] {
        var query = client.from("catalog_categories").select().eq("company_id", value: companyId)
        if let since = since { query = query.gte("updated_at", value: isoString(since)) }
        return try await query.order("updated_at", ascending: true).execute().value
    }

    func fetchDeletedCategoryIds(since: Date) async throws -> [String] {
        struct Row: Codable { let id: String }
        let rows: [Row] = try await client.from("catalog_categories")
            .select("id")
            .eq("company_id", value: companyId)
            .not("deleted_at", operator: .is, value: "null")
            .gte("deleted_at", value: isoString(since))
            .execute().value
        return rows.map(\.id)
    }

    // MARK: - Items (variant families)

    func fetchItemsForSync(since: Date? = nil) async throws -> [CatalogItemDTO] {
        var query = client.from("catalog_items").select().eq("company_id", value: companyId)
        if let since = since { query = query.gte("updated_at", value: isoString(since)) }
        return try await query.order("updated_at", ascending: true).execute().value
    }

    func fetchDeletedItemIds(since: Date) async throws -> [String] {
        struct Row: Codable { let id: String }
        let rows: [Row] = try await client.from("catalog_items")
            .select("id")
            .eq("company_id", value: companyId)
            .not("deleted_at", operator: .is, value: "null")
            .gte("deleted_at", value: isoString(since))
            .execute().value
        return rows.map(\.id)
    }

    // MARK: - Variants

    func fetchVariantsForSync(since: Date? = nil) async throws -> [CatalogVariantDTO] {
        var query = client.from("catalog_variants").select().eq("company_id", value: companyId)
        if let since = since { query = query.gte("updated_at", value: isoString(since)) }
        return try await query.order("updated_at", ascending: true).execute().value
    }

    func fetchDeletedVariantIds(since: Date) async throws -> [String] {
        struct Row: Codable { let id: String }
        let rows: [Row] = try await client.from("catalog_variants")
            .select("id")
            .eq("company_id", value: companyId)
            .not("deleted_at", operator: .is, value: "null")
            .gte("deleted_at", value: isoString(since))
            .execute().value
        return rows.map(\.id)
    }

    func adjustVariantQuantity(_ id: String, newQuantity: Double) async throws -> CatalogVariantDTO {
        var updates = UpdateCatalogVariantDTO()
        updates.quantity = newQuantity
        return try await client.from("catalog_variants")
            .update(updates).eq("id", value: id).select().single().execute().value
    }

    // MARK: - Options

    func fetchOptionsForCompany() async throws -> [CatalogOptionDTO] {
        // catalog_options has no company_id; filter via parent catalog_items.
        struct Joined: Codable {
            let id: String
            let catalogItemId: String
            let name: String
            let sortOrder: Int
            let createdAt: String
            enum CodingKeys: String, CodingKey {
                case id
                case catalogItemId  = "catalog_item_id"
                case name
                case sortOrder      = "sort_order"
                case createdAt      = "created_at"
            }
        }
        let rows: [Joined] = try await client.from("catalog_options")
            .select("id, catalog_item_id, name, sort_order, created_at, catalog_items!inner(company_id)")
            .eq("catalog_items.company_id", value: companyId)
            .execute().value
        return rows.map {
            CatalogOptionDTO(id: $0.id, catalogItemId: $0.catalogItemId,
                              name: $0.name, sortOrder: $0.sortOrder, createdAt: $0.createdAt)
        }
    }

    // MARK: - Option values

    func fetchOptionValuesForCompany() async throws -> [CatalogOptionValueDTO] {
        struct Joined: Codable {
            let id: String
            let optionId: String
            let value: String
            let sortOrder: Int
            enum CodingKeys: String, CodingKey {
                case id
                case optionId  = "option_id"
                case value
                case sortOrder = "sort_order"
            }
        }
        let rows: [Joined] = try await client.from("catalog_option_values")
            .select("id, option_id, value, sort_order, catalog_options!inner(catalog_items!inner(company_id))")
            .eq("catalog_options.catalog_items.company_id", value: companyId)
            .execute().value
        return rows.map {
            CatalogOptionValueDTO(id: $0.id, optionId: $0.optionId, value: $0.value, sortOrder: $0.sortOrder)
        }
    }

    // MARK: - Variant ↔ option-value joins

    func fetchVariantOptionValuesForCompany() async throws -> [CatalogVariantOptionValueDTO] {
        struct Joined: Codable {
            let variantId: String
            let optionValueId: String
            enum CodingKeys: String, CodingKey {
                case variantId      = "variant_id"
                case optionValueId  = "option_value_id"
            }
        }
        let rows: [Joined] = try await client.from("catalog_variant_option_values")
            .select("variant_id, option_value_id, catalog_variants!inner(company_id)")
            .eq("catalog_variants.company_id", value: companyId)
            .execute().value
        return rows.map {
            CatalogVariantOptionValueDTO(variantId: $0.variantId, optionValueId: $0.optionValueId)
        }
    }

    // MARK: - Tags + family-tag joins

    func fetchTagsForSync(since: Date? = nil) async throws -> [CatalogTagDTO] {
        var query = client.from("catalog_tags").select().eq("company_id", value: companyId)
        if let since = since { query = query.gte("updated_at", value: isoString(since)) }
        return try await query.order("updated_at", ascending: true).execute().value
    }

    func fetchItemTagsForCompany() async throws -> [CatalogItemTagDTO] {
        struct Joined: Codable {
            let id: String
            let catalogItemId: String
            let tagId: String
            enum CodingKeys: String, CodingKey {
                case id
                case catalogItemId  = "catalog_item_id"
                case tagId          = "tag_id"
            }
        }
        let rows: [Joined] = try await client.from("catalog_item_tags")
            .select("id, catalog_item_id, tag_id, catalog_items!inner(company_id)")
            .eq("catalog_items.company_id", value: companyId)
            .execute().value
        return rows.map { CatalogItemTagDTO(id: $0.id, catalogItemId: $0.catalogItemId, tagId: $0.tagId) }
    }

    // MARK: - Units

    func fetchUnitsForSync(since: Date? = nil) async throws -> [CatalogUnitDTO] {
        var query = client.from("catalog_units").select().eq("company_id", value: companyId)
        if let since = since { query = query.gte("updated_at", value: isoString(since)) }
        return try await query.order("sort_order", ascending: true).execute().value
    }

    // MARK: - Snapshots

    func fetchSnapshotsForSync(since: Date? = nil) async throws -> [CatalogSnapshotDTO] {
        var query = client.from("catalog_snapshots").select().eq("company_id", value: companyId)
        if let since = since { query = query.gte("created_at", value: isoString(since)) }
        return try await query.order("created_at", ascending: true).execute().value
    }

    func fetchSnapshotItemsForSnapshots(_ ids: [String]) async throws -> [CatalogSnapshotItemDTO] {
        guard !ids.isEmpty else { return [] }
        return try await client.from("catalog_snapshot_items").select().in("snapshot_id", values: ids).execute().value
    }

    private func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
