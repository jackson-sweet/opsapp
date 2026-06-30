//
//  BooksLedger.swift
//  OPS
//
//  Money & Leads redesign (2026-06-30) — the Money tab's ledger content. Renders
//  the flat rows for the active segment off the Books-owned VMs, resolving
//  client + crew names, applying the Books-local filter + the design's sort, and
//  routing a row tap to the existing detail screen / edit sheet. The control
//  band (segments + chips) is the pinned section header in `BooksTabView`; this
//  is the scrolling body beneath it.
//

import SwiftUI
import SwiftData

struct BooksLedger: View {
    let segment: BooksSection
    @ObservedObject var invoiceVM: InvoiceViewModel
    @ObservedObject var estimateVM: EstimateViewModel
    @ObservedObject var expenseVM: ExpenseViewModel
    let invoiceFilter: BooksInvoiceFilter
    let estimateFilter: BooksEstimateFilter
    let expenseFilter: BooksExpenseFilter

    @Query private var clients: [Client]
    @Query private var teamMembers: [TeamMember]

    @State private var selectedInvoice: Invoice?
    @State private var selectedEstimate: Estimate?
    @State private var editingExpense: ExpenseDTO?
    @State private var showCreateEstimate = false
    @State private var showCreateExpense = false

    var body: some View {
        Group {
            switch segment {
            case .invoices:  invoiceContent
            case .estimates: estimateContent
            case .expenses:  expenseContent
            }
        }
        .navigationDestination(item: $selectedInvoice) { invoice in
            InvoiceDetailView(invoice: invoice, viewModel: invoiceVM)
        }
        .navigationDestination(item: $selectedEstimate) { estimate in
            EstimateDetailView(estimate: estimate, viewModel: estimateVM)
        }
        .sheet(item: $editingExpense) { expense in
            ExpenseFormSheet(viewModel: expenseVM, editing: expense)
        }
        .sheet(isPresented: $showCreateEstimate) {
            EstimateFormSheet(viewModel: estimateVM)
        }
        .sheet(isPresented: $showCreateExpense) {
            ExpenseFormSheet(viewModel: expenseVM)
        }
    }

    // MARK: - Name resolution

    private func clientName(_ clientId: String?) -> String? {
        guard let clientId else { return nil }
        return clients.first(where: { $0.id == clientId })?.name
    }

    private func crewName(_ userId: String) -> String? {
        if let m = teamMembers.first(where: { $0.id == userId }) {
            return m.fullName.uppercased()
        }
        return nil
    }

    // MARK: - Invoices

    private var invoiceRows: [Invoice] {
        invoiceVM.invoices
            .filter(invoiceFilter.matches)
            .sorted { lhs, rhs in
                let lr = invoiceRank(lhs), rr = invoiceRank(rhs)
                if lr != rr { return lr < rr }
                return lhs.balanceDue > rhs.balanceDue
            }
    }

    @ViewBuilder
    private var invoiceContent: some View {
        if invoiceRows.isEmpty {
            if invoiceVM.invoices.isEmpty {
                BooksLedgerEmpty(value: "$0", label: "NO INVOICES", hint: "INVOICES APPEAR WHEN ESTIMATES ARE WON")
            } else {
                BooksLedgerEmpty(value: "$0", label: "NO MATCHES", hint: "NOTHING IN THIS FILTER")
            }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(invoiceRows) { invoice in
                    BooksInvoiceRow(invoice: invoice, clientName: clientName(invoice.clientId)) {
                        selectedInvoice = invoice
                    }
                }
                BooksLedgerEndMarker(text: "\(invoiceRows.count) INVOICES")
            }
        }
    }

    private func invoiceRank(_ inv: Invoice) -> Int {
        if inv.isOverdue { return 0 }
        switch inv.status {
        case .partiallyPaid:                   return 1
        case .sent, .awaitingPayment, .pastDue: return 2
        case .draft:                            return 3
        case .paid:                             return 4
        case .void, .writtenOff:                return 5
        }
    }

    // MARK: - Estimates

    private var estimateRows: [Estimate] {
        estimateVM.estimates
            .filter(estimateFilter.matches)
            .sorted { lhs, rhs in
                let lr = estimateRank(lhs), rr = estimateRank(rhs)
                if lr != rr { return lr < rr }
                return lhs.total > rhs.total
            }
    }

    @ViewBuilder
    private var estimateContent: some View {
        if estimateRows.isEmpty {
            if estimateVM.estimates.isEmpty {
                BooksLedgerEmpty(value: "$0", label: "NO ESTIMATES", hint: "QUOTE A JOB TO GET STARTED",
                                 ctaTitle: "NEW ESTIMATE", onCreate: { showCreateEstimate = true })
            } else {
                BooksLedgerEmpty(value: "$0", label: "NO MATCHES", hint: "NOTHING IN THIS FILTER")
            }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(estimateRows) { estimate in
                    BooksEstimateRow(estimate: estimate, clientName: clientName(estimate.clientId)) {
                        selectedEstimate = estimate
                    }
                }
                BooksLedgerEndMarker(text: "\(estimateRows.count) ESTIMATES")
            }
        }
    }

    private func estimateRank(_ est: Estimate) -> Int {
        switch est.status {
        case .approved:  return 0
        case .viewed:    return 1
        case .sent:      return 2
        case .converted: return 3
        case .draft:     return 4
        case .declined:  return 5
        case .expired:   return 6
        }
    }

    // MARK: - Expenses

    private var expenseRows: [ExpenseDTO] {
        expenseVM.expenses
            .filter(expenseFilter.matches)
            .sorted { expenseRank($0) < expenseRank($1) }
    }

    @ViewBuilder
    private var expenseContent: some View {
        if expenseRows.isEmpty {
            if expenseVM.expenses.isEmpty {
                BooksLedgerEmpty(value: "—", label: "NO EXPENSES", hint: "LOG WHAT YOU SPEND ON JOBS",
                                 ctaTitle: "LOG EXPENSE", onCreate: { showCreateExpense = true })
            } else {
                BooksLedgerEmpty(value: "—", label: "NOTHING TO REVIEW", hint: "EVERY EXPENSE HAS A RECEIPT + OK")
            }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(expenseRows) { expense in
                    BooksExpenseRow(expense: expense, who: crewName(expense.submittedBy)) {
                        editingExpense = expense
                    }
                }
                BooksLedgerEndMarker(text: "\(expenseRows.count) EXPENSES")
            }
        }
    }

    private func expenseRank(_ exp: ExpenseDTO) -> Int {
        if exp.receiptImageUrl?.isEmpty ?? true { return 0 }
        switch ExpenseStatus(rawValue: exp.status) {
        case .submitted:             return 1
        case .draft:                 return 2
        case .approved, .reimbursed: return 3
        case .rejected:              return 4
        case nil:                    return 5
        }
    }
}
