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
//  Rows carry the essential money actions as swipe strips (`BooksSwipeRow`) so
//  the ledger is fully actionable without opening detail: invoice → record
//  payment / void, estimate → send / convert, expense → delete. Every action
//  reuses the VM method + sheet/dialog the standalone lists already ship;
//  destructive ones confirm first.
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

    @EnvironmentObject private var dataController: DataController
    @Query private var clients: [Client]
    @Query private var teamMembers: [TeamMember]

    // Invoice/estimate detail-push selection is HOISTED to BooksTabView so its
    // navigationDestination modifiers can live outside the tab's LazyVStack — a
    // navigationDestination inside a lazy container is dropped by the nav stack
    // (SwiftUI: "will be ignored in a future release").
    @Binding var selectedInvoice: Invoice?
    @Binding var selectedEstimate: Estimate?
    @State private var editingExpense: ExpenseDTO?
    @State private var showCreateEstimate = false
    @State private var showCreateExpense = false

    // Swipe-action state — one open strip at a time, ledger-wide.
    @State private var openRowID: String?
    @State private var paymentInvoice: Invoice?
    @State private var voidTarget: Invoice?
    @State private var showVoidConfirm = false
    @State private var convertTarget: Estimate?
    @State private var showConvertConfirm = false
    @State private var deleteTarget: ExpenseDTO?
    @State private var showDeleteConfirm = false

    var body: some View {
        Group {
            switch segment {
            case .invoices:  invoiceContent
            case .estimates: estimateContent
            case .expenses:  expenseContent
            }
        }
        .onChange(of: segment) { _, _ in openRowID = nil }
        .onChange(of: invoiceFilter) { _, _ in openRowID = nil }
        .onChange(of: estimateFilter) { _, _ in openRowID = nil }
        .onChange(of: expenseFilter) { _, _ in openRowID = nil }
        // NOTE: the invoice/estimate navigationDestinations were moved UP to
        // BooksTabView (outside the ScrollView's LazyVStack). A row tap sets the
        // hoisted `selectedInvoice` / `selectedEstimate` bindings; the push is
        // wired there. Sheets/dialogs are unaffected by the lazy-container rule.
        .sheet(item: $editingExpense) { expense in
            ExpenseFormSheet(viewModel: expenseVM, editing: expense)
        }
        .sheet(isPresented: $showCreateEstimate) {
            EstimateFormSheet(viewModel: estimateVM)
        }
        .sheet(isPresented: $showCreateExpense) {
            ExpenseFormSheet(viewModel: expenseVM)
        }
        .sheet(item: $paymentInvoice) { invoice in
            PaymentRecordSheet(invoice: invoice, viewModel: invoiceVM)
        }
        .confirmationDialog("Void Invoice?", isPresented: $showVoidConfirm) {
            Button("Void Invoice", role: .destructive) {
                if let inv = voidTarget {
                    Task {
                        await invoiceVM.voidInvoice(inv)
                        if invoiceVM.error == nil {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will void the invoice. This action cannot be undone.")
        }
        .confirmationDialog("Convert to Invoice?", isPresented: $showConvertConfirm) {
            Button("Convert to Invoice") {
                if let est = convertTarget {
                    Task {
                        await estimateVM.convertToInvoice(est)
                        if estimateVM.error == nil {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            await invoiceVM.loadInvoices()   // the new invoice lands in this ledger
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will create an invoice from this estimate. This action cannot be undone.")
        }
        .confirmationDialog("Delete Expense?", isPresented: $showDeleteConfirm) {
            Button("Delete Expense", role: .destructive) {
                if let exp = deleteTarget {
                    Task {
                        await expenseVM.deleteExpense(exp.id)
                        if expenseVM.error == nil {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete the expense. This action cannot be undone.")
        }
        .errorToast($invoiceVM.error, label: Feedback.Err.operationFailed)
        .errorToast($estimateVM.error, label: Feedback.Err.operationFailed)
        .errorToast($expenseVM.error, label: Feedback.Err.operationFailed)
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
                BooksLedgerEmpty(value: "$0", label: "NO INVOICES", hint: "INVOICES COME FROM WON ESTIMATES")
            } else {
                BooksLedgerEmpty(value: "$0", label: "NO MATCHES", hint: "NOTHING IN THIS FILTER")
            }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(invoiceRows) { invoice in
                    BooksSwipeRow(
                        rowID: "invoice-\(invoice.id)",
                        leading: invoiceLeadingActions(invoice),
                        trailing: invoiceTrailingActions(invoice),
                        allowsFullSwipe: true,   // full swipe = record payment (opens the sheet — safe)
                        openRowID: $openRowID
                    ) {
                        BooksInvoiceRow(invoice: invoice, clientName: clientName(invoice.clientId)) {
                            selectedInvoice = invoice
                        }
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
                BooksLedgerEmpty(value: "$0", label: "NO ESTIMATES", hint: "QUOTE YOUR FIRST JOB",
                                 ctaTitle: "NEW ESTIMATE", onCreate: { showCreateEstimate = true })
            } else {
                BooksLedgerEmpty(value: "$0", label: "NO MATCHES", hint: "NOTHING IN THIS FILTER")
            }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(estimateRows) { estimate in
                    BooksSwipeRow(
                        rowID: "estimate-\(estimate.id)",
                        leading: estimateLeadingActions(estimate),
                        allowsFullSwipe: true,   // full swipe = send / convert (convert still confirms)
                        openRowID: $openRowID
                    ) {
                        BooksEstimateRow(estimate: estimate, clientName: clientName(estimate.clientId)) {
                            selectedEstimate = estimate
                        }
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
                    BooksSwipeRow(
                        rowID: "expense-\(expense.id)",
                        trailing: expenseTrailingActions(expense),
                        openRowID: $openRowID
                    ) {
                        BooksExpenseRow(expense: expense, who: crewName(expense.submittedBy)) {
                            editingExpense = expense
                        }
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

    // MARK: - Swipe actions (gates mirror the standalone lists exactly)

    /// PAYMENT — only while the invoice can still take one (awaiting / partial /
    /// past-due). Same `needsPayment` gate as the old embedded card.
    private func invoiceLeadingActions(_ invoice: Invoice) -> [BooksRowAction] {
        guard invoice.status.needsPayment else { return [] }
        return [BooksRowAction(
            id: "payment",
            label: "PAYMENT",
            menuTitle: "Record Payment",
            icon: "dollarsign.circle",
            tone: OPSStyle.Colors.olive
        ) { paymentInvoice = invoice }]
    }

    /// VOID — anything not already terminal (paid / void / written off).
    private func invoiceTrailingActions(_ invoice: Invoice) -> [BooksRowAction] {
        let terminal = invoice.status == .paid || invoice.status == .void || invoice.status == .writtenOff
        guard !terminal else { return [] }
        return [BooksRowAction(
            id: "void",
            label: "VOID",
            menuTitle: "Void Invoice",
            icon: OPSStyle.Icons.xmarkCircle,
            tone: OPSStyle.Colors.rose,
            isDestructive: true
        ) {
            voidTarget = invoice
            showVoidConfirm = true
        }]
    }

    /// SEND for drafts, CONVERT for approved — the estimate's one next step.
    private func estimateLeadingActions(_ estimate: Estimate) -> [BooksRowAction] {
        switch estimate.status {
        case .draft:
            return [BooksRowAction(
                id: "send",
                label: "SEND",
                menuTitle: "Send Estimate",
                icon: "paperplane",
                tone: OPSStyle.Colors.olive
            ) {
                Task {
                    await estimateVM.sendEstimate(estimate)
                    if estimateVM.error == nil {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            }]
        case .approved:
            return [BooksRowAction(
                id: "convert",
                label: "CONVERT",
                menuTitle: "Convert to Invoice",
                icon: OPSStyle.Icons.invoiceReceipt,
                tone: OPSStyle.Colors.olive
            ) {
                convertTarget = estimate
                showConvertConfirm = true
            }]
        default:
            return []
        }
    }

    /// DELETE — submitter or admin/owner, and never on approved/reimbursed
    /// lines. Mirrors `canDeleteExpense` (the server's soft-delete rule) so we
    /// don't reveal a swipe the server would reject.
    private func expenseTrailingActions(_ expense: ExpenseDTO) -> [BooksRowAction] {
        guard canDeleteExpense(expense) else { return [] }
        return [BooksRowAction(
            id: "delete",
            label: "DELETE",
            menuTitle: "Delete Expense",
            icon: OPSStyle.Icons.trash,
            tone: OPSStyle.Colors.rose,
            isDestructive: true
        ) {
            deleteTarget = expense
            showDeleteConfirm = true
        }]
    }

    private func canDeleteExpense(_ expense: ExpenseDTO) -> Bool {
        guard let user = dataController.currentUser else { return false }
        let allowed = expense.submittedBy == user.id || user.role == .admin || user.role == .owner
        let status = ExpenseStatus(rawValue: expense.status)
        return allowed && status != .approved && status != .reimbursed
    }
}
