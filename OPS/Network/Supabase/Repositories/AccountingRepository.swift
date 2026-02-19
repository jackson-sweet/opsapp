//
//  AccountingRepository.swift
//  OPS
//
//  Read-only queries for accounting dashboard data.
//

import Foundation
import Supabase

class AccountingRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    /// Fetch all invoices with balance > 0 for aging/status computations.
    func fetchAllInvoices() async throws -> [InvoiceDTO] {
        try await client
            .from("invoices")
            .select("*, invoice_line_items(*), payments(*)")
            .eq("company_id", value: companyId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }
}
