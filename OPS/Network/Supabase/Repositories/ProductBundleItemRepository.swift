//
//  ProductBundleItemRepository.swift
//  OPS
//
//  Repository for public.product_bundle_items. RLS at the DB layer scopes
//  reads/writes to the caller's company; the iOS layer also filters by
//  companyId to keep queries cheap. Soft-deletes via deleted_at — never
//  hard-deletes from this path.
//

import Foundation
import Supabase

class ProductBundleItemRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    /// Fetch every active bundle child row for the company. Cheap because
    /// the table is small (one row per child per bundle) — used by sync.
    func fetchAll() async throws -> [ProductBundleItemDTO] {
        try await client.from("product_bundle_items")
            .select()
            .eq("company_id", value: companyId)
            .is("deleted_at", value: nil)
            .order("display_order", ascending: true)
            .executeResilient(label: "product_bundle_items")
    }

    /// Fetch active children for a specific bundle. Preferred entry point
    /// for the detail/edit sheets so we don't pull the whole table.
    func fetchForBundle(_ bundleId: String) async throws -> [ProductBundleItemDTO] {
        try await client.from("product_bundle_items")
            .select()
            .eq("company_id", value: companyId)
            .eq("bundle_product_id", value: bundleId)
            .is("deleted_at", value: nil)
            .order("display_order", ascending: true)
            .execute().value
    }

    func create(_ dto: CreateProductBundleItemDTO) async throws -> ProductBundleItemDTO {
        if CatalogSchemaCapabilityGate.current.productBundleRelationshipFields {
            do {
                return try await client.from("product_bundle_items")
                    .insert(dto).select().single().execute().value
            } catch {
                CatalogSchemaCapabilityGate.recordProductBundleRelationshipFieldsUnavailable()
                guard dto.canDegradeToLegacyRequiredRow else {
                    throw CatalogSchemaCapabilityError.unavailable("product_bundle_items relationship fields")
                }
                return try await createLegacy(dto)
            }
        }
        guard dto.canDegradeToLegacyRequiredRow else {
            throw CatalogSchemaCapabilityError.unavailable("product_bundle_items relationship fields")
        }
        return try await createLegacy(dto)
    }

    func update(_ id: String, fields: UpdateProductBundleItemDTO) async throws -> ProductBundleItemDTO {
        if CatalogSchemaCapabilityGate.current.productBundleRelationshipFields {
            do {
                return try await client.from("product_bundle_items")
                    .update(fields).eq("id", value: id).select().single().execute().value
            } catch {
                CatalogSchemaCapabilityGate.recordProductBundleRelationshipFieldsUnavailable()
                guard !fields.includesRelationshipMetadata else {
                    throw CatalogSchemaCapabilityError.unavailable("product_bundle_items relationship fields")
                }
                return try await updateLegacy(id, fields: fields)
            }
        }
        guard !fields.includesRelationshipMetadata else {
            throw CatalogSchemaCapabilityError.unavailable("product_bundle_items relationship fields")
        }
        return try await updateLegacy(id, fields: fields)
    }

    func softDelete(_ id: String) async throws {
        struct SoftDelete: Codable { let deleted_at: String; let updated_at: String }
        let now = ISO8601DateFormatter().string(from: Date())
        try await client.from("product_bundle_items")
            .update(SoftDelete(deleted_at: now, updated_at: now))
            .eq("id", value: id).execute()
    }

    private func createLegacy(_ dto: CreateProductBundleItemDTO) async throws -> ProductBundleItemDTO {
        try await client.from("product_bundle_items")
            .insert(LegacyCreateProductBundleItemDTO(dto))
            .select()
            .single()
            .execute()
            .value
    }

    private func updateLegacy(_ id: String, fields: UpdateProductBundleItemDTO) async throws -> ProductBundleItemDTO {
        try await client.from("product_bundle_items")
            .update(LegacyUpdateProductBundleItemDTO(fields))
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }
}

private struct LegacyCreateProductBundleItemDTO: Codable {
    let id: String
    let companyId: String
    let bundleProductId: String
    let childProductId: String
    let quantity: Double
    let displayOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case companyId       = "company_id"
        case bundleProductId = "bundle_product_id"
        case childProductId  = "child_product_id"
        case quantity
        case displayOrder    = "display_order"
    }

    init(_ dto: CreateProductBundleItemDTO) {
        self.id = dto.id
        self.companyId = dto.companyId
        self.bundleProductId = dto.bundleProductId
        self.childProductId = dto.childProductId
        self.quantity = dto.quantity
        self.displayOrder = dto.displayOrder
    }
}

private struct LegacyUpdateProductBundleItemDTO: Codable {
    var quantity: Double?
    var displayOrder: Int?

    enum CodingKeys: String, CodingKey {
        case quantity
        case displayOrder = "display_order"
    }

    init(_ fields: UpdateProductBundleItemDTO) {
        self.quantity = fields.quantity
        self.displayOrder = fields.displayOrder
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(quantity, forKey: .quantity)
        try c.encodeIfPresent(displayOrder, forKey: .displayOrder)
    }
}
