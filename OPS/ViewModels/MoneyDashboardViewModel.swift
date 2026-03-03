//
//  MoneyDashboardViewModel.swift
//  OPS
//
//  ViewModel for Money tab dashboard — computes financial metrics
//  (sales, payments, expenses, net cash, stat carousel data) for a selected time period.
//

import SwiftUI
import SwiftData

@MainActor
class MoneyDashboardViewModel: ObservableObject {

    // MARK: - Period

    enum Period: String, CaseIterable {
        case month     = "30D"
        case quarter   = "90D"
        case sixMonths = "6M"
        case year      = "1Y"

        var label: String { rawValue }

        /// Number of calendar days this period spans.
        var days: Int {
            switch self {
            case .month:     return 30
            case .quarter:   return 90
            case .sixMonths: return 180
            case .year:      return 365
            }
        }

        /// Start date for the current period, measured backwards from now.
        var startDate: Date {
            Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        }

        /// Start date for the *prior* period (used for trend comparisons).
        var priorPeriodStartDate: Date {
            Calendar.current.date(byAdding: .day, value: -(days * 2), to: Date()) ?? Date()
        }
    }

    // MARK: - Breakdown Item

    struct BreakdownItem: Identifiable {
        let id = UUID()
        let label: String
        let amount: Double
        let date: Date?
        let entityId: String
        let type: EntityType

        enum EntityType {
            case payment
            case expense
            case invoice
        }
    }

    // MARK: - Published Properties

    @Published var selectedPeriod: Period = .month {
        didSet { recalculate() }
    }
    @Published var isLoading: Bool = false

    // Top-level metrics
    @Published var totalSales: Double = 0          // total invoiced in period
    @Published var totalPayments: Double = 0       // payments received in period
    @Published var totalExpenses: Double = 0       // expenses in period
    @Published var netCash: Double = 0             // payments minus expenses

    // Pending / overdue (all-time)
    @Published var pendingEstimatesCount: Int = 0
    @Published var pendingEstimatesValue: Double = 0
    @Published var overdueInvoicesCount: Int = 0
    @Published var overdueInvoicesValue: Double = 0

    // Stat carousel data
    @Published var closeRate: Double = 0           // % of estimates approved/converted in period
    @Published var avgDaysToPayment: Double = 0    // avg days from invoice creation to payment
    @Published var expensesTrend: Double = 0       // % change vs prior period

    // Top unpaid invoices
    @Published var topUnpaidInvoices: [(clientName: String, amount: Double, daysOverdue: Int)] = []

    // Breakdown arrays
    @Published var paymentBreakdown: [BreakdownItem] = []
    @Published var expenseBreakdown: [BreakdownItem] = []
    @Published var outstandingInvoiceBreakdown: [BreakdownItem] = []

    // MARK: - Private State

    private var estimateRepository: EstimateRepository?
    private var invoiceRepository: InvoiceRepository?
    private var expenseRepository: ExpenseRepository?
    private var modelContext: ModelContext?
    private var companyId: String?

    // Cached raw data from repositories
    private var allEstimates: [EstimateDTO] = []
    private var allInvoices: [InvoiceDTO] = []
    private var allExpenses: [ExpenseDTO] = []

    // MARK: - Setup

    /// Initialize repositories and optionally provide a ModelContext for client name lookups.
    func setup(companyId: String, modelContext: ModelContext? = nil) {
        self.companyId = companyId
        self.modelContext = modelContext
        estimateRepository = EstimateRepository(companyId: companyId)
        invoiceRepository = InvoiceRepository(companyId: companyId)
        expenseRepository = ExpenseRepository(companyId: companyId)
    }

    // MARK: - Load & Recalculate

    /// Fetch all financial data from Supabase, then compute metrics.
    func loadData() async {
        guard estimateRepository != nil,
              invoiceRepository != nil,
              expenseRepository != nil else { return }

        isLoading = true
        defer { isLoading = false }

        async let estimatesTask = fetchEstimates()
        async let invoicesTask = fetchInvoices()
        async let expensesTask = fetchExpenses()

        let (estimates, invoices, expenses) = await (estimatesTask, invoicesTask, expensesTask)

        allEstimates = estimates
        allInvoices = invoices
        allExpenses = expenses

        recalculate()
    }

    /// Recompute all metrics from cached data for the selected period.
    func recalculate() {
        let now = Date()
        let periodStart = selectedPeriod.startDate
        let priorStart = selectedPeriod.priorPeriodStartDate

        // ── Invoices in period (by createdAt) ──
        let invoicesInPeriod = allInvoices.filter { dto in
            guard let created = SupabaseDate.parse(dto.createdAt) else { return false }
            return created >= periodStart && created <= now && dto.status != InvoiceStatus.void.rawValue
        }
        totalSales = invoicesInPeriod.reduce(0) { $0 + $1.total }

        // ── Payments in period ──
        let paymentsInPeriod = allInvoices.flatMap { dto -> [PaymentDTO] in
            (dto.payments ?? []).filter { payment in
                guard let paidAt = SupabaseDate.parse(payment.paidAt) else { return false }
                return paidAt >= periodStart && paidAt <= now && !(payment.isVoid ?? false)
            }
        }
        totalPayments = paymentsInPeriod.reduce(0) { $0 + $1.amount }

        // ── Expenses in period ──
        let expensesInPeriod = allExpenses.filter { dto in
            guard dto.deletedAt == nil else { return false }
            let dateString = dto.expenseDate ?? dto.createdAt
            guard let date = SupabaseDate.parse(dateString) else { return false }
            return date >= periodStart && date <= now
        }
        totalExpenses = expensesInPeriod.reduce(0) { $0 + $1.amount }

        // ── Net cash ──
        netCash = totalPayments - totalExpenses

        // ── Pending estimates (all-time) ──
        let pendingEstimates = allEstimates.filter { dto in
            let status = EstimateStatus(rawValue: dto.status)
            return status == .sent || status == .viewed
        }
        pendingEstimatesCount = pendingEstimates.count
        pendingEstimatesValue = pendingEstimates.reduce(0) { $0 + $1.total }

        // ── Overdue invoices (all-time) ──
        let overdueInvoices = allInvoices.filter { dto in
            guard let dueDateStr = dto.dueDate,
                  let dueDate = SupabaseDate.parse(dueDateStr) else { return false }
            let status = InvoiceStatus(rawValue: dto.status)
            return dto.balanceDue > 0 && dueDate < now && status != .void
        }
        overdueInvoicesCount = overdueInvoices.count
        overdueInvoicesValue = overdueInvoices.reduce(0) { $0 + $1.balanceDue }

        // ── Close rate (estimates in period) ──
        let estimatesInPeriod = allEstimates.filter { dto in
            guard let created = SupabaseDate.parse(dto.createdAt) else { return false }
            return created >= periodStart && created <= now
        }
        let closedInPeriod = estimatesInPeriod.filter { dto in
            let status = EstimateStatus(rawValue: dto.status)
            return status == .approved || status == .converted
        }
        closeRate = estimatesInPeriod.isEmpty ? 0 : Double(closedInPeriod.count) / Double(estimatesInPeriod.count) * 100

        // ── Avg days to payment ──
        computeAvgDaysToPayment(invoicesInPeriod: invoicesInPeriod)

        // ── Expenses trend (% change vs prior period) ──
        let priorExpenses = allExpenses.filter { dto in
            guard dto.deletedAt == nil else { return false }
            let dateString = dto.expenseDate ?? dto.createdAt
            guard let date = SupabaseDate.parse(dateString) else { return false }
            return date >= priorStart && date < periodStart
        }
        let priorTotal = priorExpenses.reduce(0) { $0 + $1.amount }
        expensesTrend = priorTotal > 0
            ? ((totalExpenses - priorTotal) / priorTotal) * 100
            : (totalExpenses > 0 ? 100 : 0)

        // ── Top unpaid invoices ──
        computeTopUnpaidInvoices()

        // ── Breakdown arrays ──
        buildPaymentBreakdown(paymentsInPeriod)
        buildExpenseBreakdown(expensesInPeriod)
        buildOutstandingInvoiceBreakdown()
    }

    // MARK: - Private Helpers

    private func fetchEstimates() async -> [EstimateDTO] {
        guard let repo = estimateRepository else { return [] }
        do {
            return try await repo.fetchAll()
        } catch {
            print("[MoneyDashboard] Failed to fetch estimates: \(error.localizedDescription)")
            return []
        }
    }

    private func fetchInvoices() async -> [InvoiceDTO] {
        guard let repo = invoiceRepository else { return [] }
        do {
            return try await repo.fetchAll()
        } catch {
            print("[MoneyDashboard] Failed to fetch invoices: \(error.localizedDescription)")
            return []
        }
    }

    private func fetchExpenses() async -> [ExpenseDTO] {
        guard let repo = expenseRepository else { return [] }
        do {
            return try await repo.fetchAll()
        } catch {
            print("[MoneyDashboard] Failed to fetch expenses: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Avg Days to Payment

    private func computeAvgDaysToPayment(invoicesInPeriod: [InvoiceDTO]) {
        var totalDays: Double = 0
        var count: Int = 0

        for invoice in invoicesInPeriod {
            guard let paidAtStr = invoice.paidAt,
                  let paidAt = SupabaseDate.parse(paidAtStr),
                  let createdAt = SupabaseDate.parse(invoice.createdAt) else { continue }
            let days = Calendar.current.dateComponents([.day], from: createdAt, to: paidAt).day ?? 0
            totalDays += Double(max(0, days))
            count += 1
        }

        avgDaysToPayment = count > 0 ? totalDays / Double(count) : 0
    }

    // MARK: - Top Unpaid Invoices

    private func computeTopUnpaidInvoices() {
        let now = Date()

        // Filter to invoices with a balance due that are not void
        let unpaid = allInvoices.filter { dto in
            let status = InvoiceStatus(rawValue: dto.status)
            return dto.balanceDue > 0 && status != .void
        }

        // Sort by balance due descending, take top 3
        let top3 = unpaid
            .sorted { $0.balanceDue > $1.balanceDue }
            .prefix(3)

        // Build client name lookup from ModelContext if available
        let clientNames = lookupClientNames(for: top3.compactMap { $0.clientId })

        topUnpaidInvoices = top3.map { dto in
            let clientName: String
            if let cid = dto.clientId, let name = clientNames[cid] {
                clientName = name
            } else {
                clientName = dto.title ?? dto.invoiceNumber
            }

            var daysOverdue = 0
            if let dueDateStr = dto.dueDate,
               let dueDate = SupabaseDate.parse(dueDateStr),
               dueDate < now {
                daysOverdue = max(0, Calendar.current.dateComponents([.day], from: dueDate, to: now).day ?? 0)
            }

            return (clientName: clientName, amount: dto.balanceDue, daysOverdue: daysOverdue)
        }
    }

    /// Look up client names from SwiftData. Returns [clientId: name].
    private func lookupClientNames(for clientIds: [String]) -> [String: String] {
        guard let context = modelContext, !clientIds.isEmpty else { return [:] }

        var result: [String: String] = [:]
        do {
            let descriptor = FetchDescriptor<Client>()
            let allClients = try context.fetch(descriptor)
            for client in allClients where clientIds.contains(client.id) {
                result[client.id] = client.name
            }
        } catch {
            print("[MoneyDashboard] Failed to fetch clients: \(error.localizedDescription)")
        }
        return result
    }

    // MARK: - Breakdown Builders

    private func buildPaymentBreakdown(_ payments: [PaymentDTO]) {
        paymentBreakdown = payments
            .sorted { SupabaseDate.parse($0.paidAt) ?? Date.distantPast > SupabaseDate.parse($1.paidAt) ?? Date.distantPast }
            .map { payment in
                let method = PaymentMethod(rawValue: payment.method)?.displayName ?? payment.method.uppercased()
                let invoiceNum = invoiceNumber(for: payment.invoiceId)
                let label = "\(invoiceNum) — \(method)"
                return BreakdownItem(
                    label: label,
                    amount: payment.amount,
                    date: SupabaseDate.parse(payment.paidAt),
                    entityId: payment.invoiceId,
                    type: .payment
                )
            }
    }

    private func buildExpenseBreakdown(_ expenses: [ExpenseDTO]) {
        expenseBreakdown = expenses
            .sorted {
                let d0 = SupabaseDate.parse($0.expenseDate ?? $0.createdAt) ?? Date.distantPast
                let d1 = SupabaseDate.parse($1.expenseDate ?? $1.createdAt) ?? Date.distantPast
                return d0 > d1
            }
            .map { expense in
                let label = expense.merchantName ?? expense.description ?? "Expense"
                let dateString = expense.expenseDate ?? expense.createdAt
                return BreakdownItem(
                    label: label,
                    amount: expense.amount,
                    date: SupabaseDate.parse(dateString),
                    entityId: expense.id,
                    type: .expense
                )
            }
    }

    private func buildOutstandingInvoiceBreakdown() {
        let outstanding = allInvoices.filter { dto in
            let status = InvoiceStatus(rawValue: dto.status)
            return dto.balanceDue > 0 && status != .void
        }
        .sorted { $0.balanceDue > $1.balanceDue }

        let clientNames = lookupClientNames(for: outstanding.compactMap { $0.clientId })

        outstandingInvoiceBreakdown = outstanding.map { dto in
            let label: String
            if let cid = dto.clientId, let name = clientNames[cid] {
                label = "\(name) — \(dto.invoiceNumber)"
            } else {
                label = dto.title ?? dto.invoiceNumber
            }

            return BreakdownItem(
                label: label,
                amount: dto.balanceDue,
                date: dto.dueDate.flatMap { SupabaseDate.parse($0) },
                entityId: dto.id,
                type: .invoice
            )
        }
    }

    /// Look up the invoice number for a given invoice ID from cached data.
    private func invoiceNumber(for invoiceId: String) -> String {
        allInvoices.first(where: { $0.id == invoiceId })?.invoiceNumber ?? "INV"
    }
}
