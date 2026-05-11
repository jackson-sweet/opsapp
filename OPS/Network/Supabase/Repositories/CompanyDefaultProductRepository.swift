//
//  CompanyDefaultProductRepository.swift
//  OPS
//

import Foundation
import Supabase

class CompanyDefaultProductRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    func fetchAll() async throws -> [CompanyDefaultProductDTO] {
        try await client.from("company_default_products")
            .select().eq("company_id", value: companyId).execute().value
    }

    func upsert(_ dto: UpsertCompanyDefaultProductDTO) async throws -> CompanyDefaultProductDTO {
        try await client.from("company_default_products").upsert(dto, onConflict: "company_id,component_type")
            .select().single().execute().value
    }

    func remove(componentType: String) async throws {
        try await client.from("company_default_products")
            .delete()
            .eq("company_id", value: companyId)
            .eq("component_type", value: componentType)
            .execute()
    }
}
