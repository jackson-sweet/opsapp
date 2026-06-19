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

    // MARK: - Catalog setup RPC

    func saveCatalogSetup(
        idempotencyKey: String,
        payload: CatalogSetupSavePayload
    ) async throws -> CatalogSetupSaveResponse {
        let params = CatalogSetupSaveRPCParams(
            p_company_id: companyId,
            p_idempotency_key: idempotencyKey,
            p_payload: payload
        )
        return try await client.rpc("catalog_setup_save", params: params).execute().value
    }

    // MARK: - Categories

    func fetchCategoriesForSync(since: Date? = nil) async throws -> [CatalogCategoryDTO] {
        var query = client.from("catalog_categories").select().eq("company_id", value: companyId)
        if let since = since { query = query.gte("updated_at", value: isoString(since)) }
        return try await query.order("updated_at", ascending: true).executeResilient(label: "catalog")
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

    func createCategory(_ dto: CreateCatalogCategoryDTO) async throws -> CatalogCategoryDTO {
        try await client.from("catalog_categories")
            .insert(dto).select().single().execute().value
    }

    func updateCategory(_ id: String, fields: UpdateCatalogCategoryDTO) async throws -> CatalogCategoryDTO {
        try await client.from("catalog_categories")
            .update(fields).eq("id", value: id).select().single().execute().value
    }

    func softDeleteCategory(_ id: String) async throws {
        struct SoftDelete: Codable { let deleted_at: String; let updated_at: String }
        let now = isoString(Date())
        try await client.from("catalog_categories")
            .update(SoftDelete(deleted_at: now, updated_at: now))
            .eq("id", value: id).execute()
    }

    // MARK: - Items (variant families)

    func fetchItemsForSync(since: Date? = nil) async throws -> [CatalogItemDTO] {
        var query = client.from("catalog_items").select().eq("company_id", value: companyId)
        if let since = since { query = query.gte("updated_at", value: isoString(since)) }
        return try await query.order("updated_at", ascending: true).executeResilient(label: "catalog")
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
        return try await query.order("updated_at", ascending: true).executeResilient(label: "catalog")
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

    func createVariant(_ dto: CreateCatalogVariantDTO) async throws -> CatalogVariantDTO {
        try await client.from("catalog_variants")
            .insert(dto).select().single().execute().value
    }

    func updateVariant(_ id: String, fields: UpdateCatalogVariantDTO) async throws -> CatalogVariantDTO {
        try await client.from("catalog_variants")
            .update(fields).eq("id", value: id).select().single().execute().value
    }

    func softDeleteVariant(_ id: String) async throws {
        struct SoftDelete: Codable { let deleted_at: String; let updated_at: String }
        let now = isoString(Date())
        try await client.from("catalog_variants")
            .update(SoftDelete(deleted_at: now, updated_at: now))
            .eq("id", value: id).execute()
    }

    // MARK: - Family writes

    func createFamily(_ dto: CreateCatalogItemDTO) async throws -> CatalogItemDTO {
        try await client.from("catalog_items")
            .insert(dto).select().single().execute().value
    }

    /// Convenience for the iOS // SHOW IN STOCK toggle's "create new" path.
    /// Creates a `catalog_items` family + a single default `catalog_variants`
    /// row (no option pins, qty 0) in two round-trips. Returns the family id
    /// so the caller can write `products.linked_catalog_item_id`.
    /// Bug 164e0595 — New Product Sheet redesign.
    func createDefaultItemForProduct(
        companyId: String,
        productName: String,
        categoryId: String?,
        defaultPrice: Double?,
        defaultUnitCost: Double?,
        defaultUnitId: String?
    ) async throws -> CatalogItemDTO {
        let familyDTO = CreateCatalogItemDTO(
            companyId: companyId,
            categoryId: categoryId,
            name: productName,
            description: nil,
            defaultPrice: defaultPrice,
            defaultUnitCost: defaultUnitCost,
            defaultWarningThreshold: nil,
            defaultCriticalThreshold: nil,
            defaultUnitId: defaultUnitId
        )
        let createdFamily = try await createFamily(familyDTO)

        let variantDTO = CreateCatalogVariantDTO(
            companyId: companyId,
            catalogItemId: createdFamily.id,
            sku: nil,
            quantity: 0,
            priceOverride: nil,
            unitCostOverride: nil,
            warningThreshold: nil,
            criticalThreshold: nil,
            unitId: defaultUnitId
        )
        _ = try await createVariant(variantDTO)

        return createdFamily
    }

    func updateFamily(_ id: String, fields: UpdateCatalogItemDTO) async throws -> CatalogItemDTO {
        try await client.from("catalog_items")
            .update(fields).eq("id", value: id).select().single().execute().value
    }

    func softDeleteFamily(_ id: String) async throws {
        struct SoftDelete: Codable { let deleted_at: String; let updated_at: String }
        let now = isoString(Date())
        try await client.from("catalog_items")
            .update(SoftDelete(deleted_at: now, updated_at: now))
            .eq("id", value: id).execute()
    }

    // MARK: - Variant ↔ option-value writes

    func createOption(_ dto: CreateCatalogOptionDTO) async throws -> CatalogOptionDTO {
        try await client.from("catalog_options")
            .insert(dto).select().single().execute().value
    }

    func createOptionValue(_ dto: CreateCatalogOptionValueDTO) async throws -> CatalogOptionValueDTO {
        try await client.from("catalog_option_values")
            .insert(dto).select().single().execute().value
    }

    func createVariantOptionValue(variantId: String, optionValueId: String) async throws {
        let dto = UpsertCatalogVariantOptionValueDTO(variantId: variantId, optionValueId: optionValueId)
        try await client.from("catalog_variant_option_values")
            .insert(dto).execute()
    }

    func deleteVariantOptionValues(variantId: String) async throws {
        try await client.from("catalog_variant_option_values")
            .delete().eq("variant_id", value: variantId).execute()
    }

    func replaceVariantOptionValues(variantId: String, optionValueIds: [String]) async throws {
        try await deleteVariantOptionValues(variantId: variantId)
        for optionValueId in optionValueIds {
            try await createVariantOptionValue(variantId: variantId, optionValueId: optionValueId)
        }
    }

    // MARK: - Inventory deduction audit log

    /// Records a row in `inventory_deductions` for a manual variant
    /// adjustment. Best-effort: failures should not block the user since
    /// the underlying quantity update has already succeeded by the time
    /// this is called.
    func recordVariantDeduction(
        id: String,
        catalogVariantId: String,
        previousQuantity: Double,
        newQuantity: Double,
        deductedBy: String?,
        reason: String,
        projectId: String? = nil,
        taskId: String? = nil,
        notes: String? = nil
    ) async throws {
        let dto = CreateInventoryDeductionDTO(
            id: id,
            companyId: companyId,
            catalogVariantId: catalogVariantId,
            projectId: projectId,
            taskId: taskId,
            quantityDeducted: previousQuantity - newQuantity,
            previousQuantity: previousQuantity,
            newQuantity: newQuantity,
            reason: reason,
            deductedBy: deductedBy,
            notes: notes
        )
        try await client.from("inventory_deductions").insert(dto).execute()
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
            .executeResilient(label: "catalog")
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
            .executeResilient(label: "catalog")
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
            .executeResilient(label: "catalog")
        return rows.map {
            CatalogVariantOptionValueDTO(variantId: $0.variantId, optionValueId: $0.optionValueId)
        }
    }

    // MARK: - Tags + family-tag joins

    func fetchTagsForSync(since: Date? = nil) async throws -> [CatalogTagDTO] {
        var query = client.from("catalog_tags").select().eq("company_id", value: companyId)
        if let since = since { query = query.gte("updated_at", value: isoString(since)) }
        return try await query.order("updated_at", ascending: true).executeResilient(label: "catalog")
    }

    func createTag(_ dto: CreateCatalogTagDTO) async throws -> CatalogTagDTO {
        try await client.from("catalog_tags")
            .insert(dto).select().single().execute().value
    }

    func updateTag(_ id: String, fields: UpdateCatalogTagDTO) async throws -> CatalogTagDTO {
        try await client.from("catalog_tags")
            .update(fields).eq("id", value: id).select().single().execute().value
    }

    func softDeleteTag(_ id: String) async throws {
        struct SoftDelete: Codable { let deleted_at: String; let updated_at: String }
        let now = isoString(Date())
        try await client.from("catalog_tags")
            .update(SoftDelete(deleted_at: now, updated_at: now))
            .eq("id", value: id).execute()
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
            .executeResilient(label: "catalog")
        return rows.map { CatalogItemTagDTO(id: $0.id, catalogItemId: $0.catalogItemId, tagId: $0.tagId) }
    }

    func replaceFamilyTags(catalogItemId: String, tagIds: Set<String>) async throws -> [CatalogItemTagDTO] {
        try await client.from("catalog_item_tags")
            .delete()
            .eq("catalog_item_id", value: catalogItemId)
            .execute()

        let uniqueTagIds = tagIds.sorted()
        guard !uniqueTagIds.isEmpty else { return [] }

        let rows = uniqueTagIds.map {
            CreateCatalogItemTagDTO(catalogItemId: catalogItemId, tagId: $0)
        }
        return try await client.from("catalog_item_tags")
            .insert(rows)
            .select()
            .execute()
            .value
    }

    // MARK: - Units

    func fetchUnitsForSync(since: Date? = nil) async throws -> [CatalogUnitDTO] {
        var query = client.from("catalog_units").select().eq("company_id", value: companyId)
        if let since = since { query = query.gte("updated_at", value: isoString(since)) }
        return try await query.order("sort_order", ascending: true).executeResilient(label: "catalog")
    }

    func createUnit(_ dto: CreateCatalogUnitDTO) async throws -> CatalogUnitDTO {
        try await client.from("catalog_units")
            .insert(dto).select().single().execute().value
    }

    func updateUnit(_ id: String, fields: UpdateCatalogUnitDTO) async throws -> CatalogUnitDTO {
        try await client.from("catalog_units")
            .update(fields).eq("id", value: id).select().single().execute().value
    }

    func softDeleteUnit(_ id: String) async throws {
        struct SoftDelete: Codable { let deleted_at: String; let updated_at: String }
        let now = isoString(Date())
        try await client.from("catalog_units")
            .update(SoftDelete(deleted_at: now, updated_at: now))
            .eq("id", value: id).execute()
    }

    // MARK: - Snapshots

    func fetchSnapshotsForSync(since: Date? = nil) async throws -> [CatalogSnapshotDTO] {
        var query = client.from("catalog_snapshots").select().eq("company_id", value: companyId)
        if let since = since { query = query.gte("created_at", value: isoString(since)) }
        return try await query.order("created_at", ascending: true).executeResilient(label: "catalog")
    }

    func fetchSnapshotItemsForSnapshots(_ ids: [String]) async throws -> [CatalogSnapshotItemDTO] {
        guard !ids.isEmpty else { return [] }
        return try await client.from("catalog_snapshot_items").select().in("snapshot_id", values: ids).executeResilient(label: "catalog")
    }

    private func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private struct CatalogSetupSaveRPCParams: Encodable {
    let p_company_id: String
    let p_idempotency_key: String
    let p_payload: CatalogSetupSavePayload
}
