//
//  InvoiceViewModel.swift
//  OPS
//
//  ViewModel for Invoices — reads from SwiftData (populated via InboundProcessor),
//  performs server mutations, and refreshes local records from the server when needed.
//

import SwiftUI
import SwiftData

@MainActor
class InvoiceViewModel: ObservableObject {
    @Published var invoices: [Invoice] = []
    @Published var selectedFilter: InvoiceFilter = .all
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String? = nil

    private var repository: InvoiceRepository?
    private var modelContext: ModelContext?

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

    func setup(companyId: String, modelContext: ModelContext) {
        self.repository = InvoiceRepository(companyId: companyId)
        self.modelContext = modelContext
        reloadFromLocal()
    }

    /// Re-read invoices from the local SwiftData store. Call after a sync or mutation.
    ///
    /// Runs on the main thread because SwiftData's ModelContext is not thread-safe.
    /// A fetch limit caps the worst-case hitch for companies with very large invoice
    /// histories — 500 most-recent invoices is plenty for the list UI, and any deeper
    /// history is reachable via search (which queries SwiftData directly) or pagination.
    func reloadFromLocal() {
        guard let ctx = modelContext else { return }
        var descriptor = FetchDescriptor<Invoice>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        invoices = (try? ctx.fetch(descriptor)) ?? []
    }

    /// Legacy entry point — kept for callers that expect an explicit load.
    /// Now just re-reads from SwiftData; server sync is owned by InboundProcessor.
    func loadInvoices() async {
        reloadFromLocal()
    }

    func lineItems(for invoiceId: String) -> [InvoiceLineItem] {
        guard let ctx = modelContext else { return [] }
        let descriptor = FetchDescriptor<InvoiceLineItem>(
            predicate: #Predicate { $0.invoiceId == invoiceId },
            sortBy: [SortDescriptor(\.displayOrder)]
        )
        return (try? ctx.fetch(descriptor)) ?? []
    }

    func payments(for invoiceId: String) -> [Payment] {
        guard let ctx = modelContext else { return [] }
        let descriptor = FetchDescriptor<Payment>(
            predicate: #Predicate { $0.invoiceId == invoiceId },
            sortBy: [SortDescriptor(\.paidAt, order: .reverse)]
        )
        return (try? ctx.fetch(descriptor)) ?? []
    }

    func recordPayment(invoiceId: String, companyId: String, clientId: String, amount: Double, method: PaymentMethod, notes: String?) async {
        guard let repo = repository else { return }
        let dto = CreatePaymentDTO(
            invoiceId: invoiceId,
            companyId: companyId,
            clientId: clientId,
            amount: amount,
            paymentMethod: method.rawValue,
            reference: nil,
            notes: notes
        )
        do {
            _ = try await repo.recordPayment(dto)
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
            await refreshInvoice(invoice.id)
        } catch {
            invoice.status = originalStatus
            self.error = error.localizedDescription
        }
    }

    func sendInvoice(_ invoice: Invoice) async {
        await updateStatus(invoice, to: .sent)
    }

    func writeOffInvoice(_ invoice: Invoice) async {
        await updateStatus(invoice, to: .writtenOff)
    }

    private func updateStatus(_ invoice: Invoice, to status: InvoiceStatus) async {
        guard let repo = repository else { return }
        let originalStatus = invoice.status
        invoice.status = status
        do {
            try await repo.updateStatus(invoice.id, status: status)
            await refreshInvoice(invoice.id)
        } catch {
            invoice.status = originalStatus
            self.error = error.localizedDescription
        }
    }

    /// Targeted refresh from server — used for Spotlight taps that land on a stale
    /// local copy or after a mutation that should immediately reflect server state.
    func refreshFromServer(invoiceId: String) async {
        await refreshInvoice(invoiceId)
    }

    private func refreshInvoice(_ invoiceId: String) async {
        guard let repo = repository, let ctx = modelContext else { return }
        do {
            let dto = try await repo.fetchOne(invoiceId)
            let descriptor = FetchDescriptor<Invoice>(
                predicate: #Predicate { $0.id == invoiceId }
            )
            if let existing = try ctx.fetch(descriptor).first {
                let fresh = dto.toModel()
                existing.status = fresh.status
                existing.subtotal = fresh.subtotal
                existing.taxAmount = fresh.taxAmount
                existing.total = fresh.total
                existing.amountPaid = fresh.amountPaid
                existing.balanceDue = fresh.balanceDue
                existing.dueDate = fresh.dueDate
                existing.sentAt = fresh.sentAt
                existing.paidAt = fresh.paidAt
                existing.updatedAt = fresh.updatedAt
                existing.lastSyncedAt = Date()
            } else {
                let model = dto.toModel()
                model.lastSyncedAt = Date()
                ctx.insert(model)
            }

            // Merge fresh line items and payments
            if let lineItems = dto.lineItems {
                for liDTO in lineItems {
                    let liId = liDTO.id
                    let liDescriptor = FetchDescriptor<InvoiceLineItem>(
                        predicate: #Predicate { $0.id == liId }
                    )
                    if try ctx.fetch(liDescriptor).first == nil {
                        ctx.insert(liDTO.toModel())
                    }
                }
            }
            if let payments = dto.payments {
                for pDTO in payments {
                    let pId = pDTO.id
                    let pDescriptor = FetchDescriptor<Payment>(
                        predicate: #Predicate { $0.id == pId }
                    )
                    if try ctx.fetch(pDescriptor).first == nil {
                        ctx.insert(pDTO.toModel())
                    }
                }
            }

            try ctx.save()
            reloadFromLocal()
        } catch {
            // Silently fail on refresh
        }
    }
}
