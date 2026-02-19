//
//  EstimateRepository.swift
//  OPS
//
//  Repository for Estimate operations via Supabase.
//

import Foundation
import Supabase

class EstimateRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    func fetchAll() async throws -> [EstimateDTO] {
        try await client
            .from("estimates")
            .select("*, estimate_line_items(*)")
            .eq("company_id", value: companyId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func create(_ dto: CreateEstimateDTO) async throws -> EstimateDTO {
        try await client
            .from("estimates")
            .insert(dto)
            .select("*, estimate_line_items(*)")
            .single()
            .execute()
            .value
    }

    func addLineItem(_ dto: CreateLineItemDTO) async throws -> EstimateLineItemDTO {
        try await client
            .from("estimate_line_items")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    func updateLineItem(_ id: String, fields: UpdateLineItemDTO) async throws -> EstimateLineItemDTO {
        try await client
            .from("estimate_line_items")
            .update(fields)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    func deleteLineItem(_ id: String) async throws {
        try await client
            .from("estimate_line_items")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    func updateStatus(_ estimateId: String, status: EstimateStatus) async throws -> EstimateDTO {
        try await client
            .from("estimates")
            .update(["status": status.rawValue])
            .eq("id", value: estimateId)
            .select("*, estimate_line_items(*)")
            .single()
            .execute()
            .value
    }

    /// Convert approved estimate to invoice — atomic RPC, never do this manually.
    func convertToInvoice(estimateId: String) async throws -> InvoiceDTO {
        try await client
            .rpc("convert_estimate_to_invoice", params: ["p_estimate_id": estimateId])
            .execute()
            .value
    }
}
