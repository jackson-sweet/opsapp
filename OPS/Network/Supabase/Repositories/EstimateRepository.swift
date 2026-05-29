//
//  EstimateRepository.swift
//  OPS
//
//  Repository for Estimate operations via Supabase.
//

import Foundation
import Supabase

protocol EstimateAcceptanceClient {
    func acceptEstimateToJob(
        estimateId: String,
        idempotencyKey: String
    ) async throws -> AcceptEstimateToJobResponseDTO
}

class EstimateRepository: EstimateAcceptanceClient {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    func fetchAll(since: Date? = nil) async throws -> [EstimateDTO] {
        var query = client
            .from("estimates")
            .select("*, line_items(*)")
            .eq("company_id", value: companyId)

        if let since = since {
            query = query.gte("updated_at", value: isoString(since))
        }

        return try await query
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchDeletedIds(since: Date) async throws -> [String] {
        struct IdRow: Codable { let id: String }
        let rows: [IdRow] = try await client
            .from("estimates")
            .select("id")
            .eq("company_id", value: companyId)
            .not("deleted_at", operator: .is, value: "null")
            .gte("deleted_at", value: isoString(since))
            .execute()
            .value
        return rows.map { $0.id }
    }

    private func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    func fetchOne(_ estimateId: String) async throws -> EstimateDTO {
        try await client
            .from("estimates")
            .select("*, line_items(*)")
            .eq("id", value: estimateId)
            .single()
            .execute()
            .value
    }

    func updateTitle(_ estimateId: String, title: String) async throws {
        try await client
            .from("estimates")
            .update(["title": title])
            .eq("id", value: estimateId)
            .execute()
    }

    func create(_ dto: CreateEstimateDTO) async throws -> EstimateDTO {
        try await client
            .from("estimates")
            .insert(dto)
            .select("*, line_items(*)")
            .single()
            .execute()
            .value
    }

    func addLineItem(_ dto: CreateLineItemDTO) async throws -> EstimateLineItemDTO {
        try await client
            .from("line_items")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    func updateLineItem(_ id: String, fields: UpdateLineItemDTO) async throws -> EstimateLineItemDTO {
        try await client
            .from("line_items")
            .update(fields)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    func deleteLineItem(_ id: String) async throws {
        try await client
            .from("line_items")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    func updateStatus(_ estimateId: String, status: EstimateStatus) async throws -> EstimateDTO {
        try await client
            .from("estimates")
            .update(["status": status.rawValue])
            .eq("id", value: estimateId)
            .select("*, line_items(*)")
            .single()
            .execute()
            .value
    }

    /// Accept estimate and let Supabase atomically create the job, projected demand, and mapping notifications.
    func acceptEstimateToJob(
        estimateId: String,
        idempotencyKey: String
    ) async throws -> AcceptEstimateToJobResponseDTO {
        struct Params: Encodable {
            let p_estimate_id: String
            let p_idempotency_key: String
        }

        return try await client
            .rpc(
                "accept_estimate_to_job",
                params: Params(
                    p_estimate_id: estimateId,
                    p_idempotency_key: idempotencyKey
                )
            )
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

    /// Create a progress invoice from selected line items at specified percentages.
    /// Estimate stays approved (not converted) — multiple progress invoices are allowed.
    func createProgressInvoice(estimateId: String, lineItemSelections: [(lineItemId: String, percentage: Double)]) async throws -> String {
        struct Params: Encodable {
            let p_estimate_id: String
            let p_line_item_selections: [Selection]

            struct Selection: Encodable {
                let line_item_id: String
                let percentage: Double
            }
        }

        let params = Params(
            p_estimate_id: estimateId,
            p_line_item_selections: lineItemSelections.map {
                Params.Selection(line_item_id: $0.lineItemId, percentage: $0.percentage)
            }
        )

        let invoiceId: String = try await client
            .rpc("create_progress_invoice", params: params)
            .execute()
            .value

        return invoiceId
    }
}
