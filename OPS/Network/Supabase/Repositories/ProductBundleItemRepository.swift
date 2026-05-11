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
            .execute().value
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
        try await client.from("product_bundle_items")
            .insert(dto).select().single().execute().value
    }

    func update(_ id: String, fields: UpdateProductBundleItemDTO) async throws -> ProductBundleItemDTO {
        try await client.from("product_bundle_items")
            .update(fields).eq("id", value: id).select().single().execute().value
    }

    func softDelete(_ id: String) async throws {
        struct SoftDelete: Codable { let deleted_at: String; let updated_at: String }
        let now = ISO8601DateFormatter().string(from: Date())
        try await client.from("product_bundle_items")
            .update(SoftDelete(deleted_at: now, updated_at: now))
            .eq("id", value: id).execute()
    }
}
