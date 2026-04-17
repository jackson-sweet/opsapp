//
//  InvoiceRepository.swift
//  OPS
//
//  Repository for Invoice operations via Supabase.
//

import Foundation
import Supabase

class InvoiceRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    func fetchAll(since: Date? = nil) async throws -> [InvoiceDTO] {
        var query = client
            .from("invoices")
            .select("*, line_items(*), payments(*)")
            .eq("company_id", value: companyId)

        if let since = since {
            query = query.gte("updated_at", value: isoString(since))
        }

        return try await query
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// Fetch IDs of invoices soft-deleted since the given date (for delta sync removal).
    func fetchDeletedIds(since: Date) async throws -> [String] {
        struct IdRow: Codable { let id: String }
        let rows: [IdRow] = try await client
            .from("invoices")
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

    func fetchOne(_ invoiceId: String) async throws -> InvoiceDTO {
        try await client
            .from("invoices")
            .select("*, line_items(*), payments(*)")
            .eq("id", value: invoiceId)
            .single()
            .execute()
            .value
    }

    func recordPayment(_ dto: CreatePaymentDTO) async throws -> PaymentDTO {
        // Insert only — DB trigger maintains invoice balance and status automatically.
        // NEVER update invoice.amount_paid or invoice.balance_due manually.
        try await client
            .from("payments")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    func updateStatus(_ invoiceId: String, status: InvoiceStatus) async throws {
        try await client
            .from("invoices")
            .update(["status": status.rawValue])
            .eq("id", value: invoiceId)
            .execute()
    }

    func voidInvoice(_ invoiceId: String) async throws {
        try await updateStatus(invoiceId, status: .void)
    }
}
