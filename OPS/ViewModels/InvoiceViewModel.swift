//
//  InvoiceViewModel.swift
//  OPS
//
//  ViewModel for Invoices — manages invoice list, filtering, payments, and status actions.
//

import SwiftUI

@MainActor
class InvoiceViewModel: ObservableObject {
    @Published var invoices: [Invoice] = []
    @Published var selectedFilter: InvoiceFilter = .all
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String? = nil

    private var repository: InvoiceRepository?
    private var lineItemDTOs: [String: [InvoiceLineItemDTO]] = [:]
    private var paymentDTOs: [String: [PaymentDTO]] = [:]

    enum InvoiceFilter: String, CaseIterable {
        case all      = "ALL"
        case unpaid   = "UNPAID"
        case overdue  = "OVERDUE"
        case paid     = "PAID"
    }

    var filteredInvoices: [Invoice] {
        var result = invoices
        switch selectedFilter {
        case .all:     break
        case .unpaid:  result = result.filter { $0.status.needsPayment }
        case .overdue: result = result.filter { $0.isOverdue }
        case .paid:    result = result.filter { $0.status.isPaid }
        }
        if !searchText.isEmpty {
            result = result.filter {
                ($0.title ?? "").localizedCaseInsensitiveContains(searchText) ||
                $0.invoiceNumber.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    func setup(companyId: String) {
        repository = InvoiceRepository(companyId: companyId)
    }

    func loadInvoices() async {
        guard let repo = repository else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let dtos = try await repo.fetchAll()
            invoices = dtos.map { dto in
                let inv = dto.toModel()
                lineItemDTOs[inv.id] = dto.lineItems
                paymentDTOs[inv.id] = dto.payments
                return inv
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func lineItems(for invoiceId: String) -> [InvoiceLineItem] {
        lineItemDTOs[invoiceId]?.map { $0.toModel() } ?? []
    }

    func payments(for invoiceId: String) -> [Payment] {
        paymentDTOs[invoiceId]?.map { $0.toModel() } ?? []
    }

    func recordPayment(invoiceId: String, companyId: String, amount: Double, method: PaymentMethod, notes: String?) async {
        guard let repo = repository else { return }
        let dto = CreatePaymentDTO(
            invoiceId: invoiceId,
            companyId: companyId,
            amount: amount,
            method: method.rawValue,
            reference: nil,
            notes: notes
        )
        do {
            _ = try await repo.recordPayment(dto)
            // CRITICAL: Re-fetch invoice to get DB-trigger-updated balance/status
            await refreshInvoice(invoiceId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func voidInvoice(_ invoice: Invoice) async {
        guard let repo = repository else { return }
        let originalStatus = invoice.status
        invoice.status = .void
        do {
            try await repo.voidInvoice(invoice.id)
        } catch {
            invoice.status = originalStatus
            self.error = error.localizedDescription
        }
    }

    func sendInvoice(_ invoice: Invoice) async {
        await updateStatus(invoice, to: .sent)
    }

    private func updateStatus(_ invoice: Invoice, to status: InvoiceStatus) async {
        guard let repo = repository else { return }
        let originalStatus = invoice.status
        invoice.status = status
        do {
            try await repo.updateStatus(invoice.id, status: status)
        } catch {
            invoice.status = originalStatus
            self.error = error.localizedDescription
        }
    }

    private func refreshInvoice(_ invoiceId: String) async {
        guard let repo = repository else { return }
        do {
            let allDTOs = try await repo.fetchAll()
            if let dto = allDTOs.first(where: { $0.id == invoiceId }),
               let idx = invoices.firstIndex(where: { $0.id == invoiceId }) {
                let refreshed = dto.toModel()
                lineItemDTOs[invoiceId] = dto.lineItems
                paymentDTOs[invoiceId] = dto.payments
                invoices[idx] = refreshed
            }
        } catch {
            // Silently fail on refresh
        }
    }
}
