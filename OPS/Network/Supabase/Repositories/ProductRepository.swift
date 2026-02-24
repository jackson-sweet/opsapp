//
//  ProductRepository.swift
//  OPS
//
//  Repository for Product/Service catalog operations via Supabase.
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

    func fetchAll() async throws -> [ProductDTO] {
        try await client
            .from("products")
            .select()
            .eq("company_id", value: companyId)
            .eq("is_active", value: true)
            .order("name", ascending: true)
            .execute()
            .value
    }

    func create(_ dto: CreateProductDTO) async throws -> ProductDTO {
        try await client
            .from("products")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    func update(_ id: String, fields: UpdateProductDTO) async throws -> ProductDTO {
        try await client
            .from("products")
            .update(fields)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    func deactivate(_ id: String) async throws {
        try await client
            .from("products")
            .update(["is_active": false])
            .eq("id", value: id)
            .execute()
    }
}
