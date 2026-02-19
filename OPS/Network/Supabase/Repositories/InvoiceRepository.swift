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

    func fetchAll() async throws -> [InvoiceDTO] {
        try await client
            .from("invoices")
            .select("*, invoice_line_items(*), payments(*)")
            .eq("company_id", value: companyId)
            .order("created_at", ascending: false)
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
