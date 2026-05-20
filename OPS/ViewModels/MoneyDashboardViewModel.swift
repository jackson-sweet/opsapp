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
        case month       = "30D"      // Trailing 30 days
        case quarter     = "90D"      // Trailing 90 days
        case sixMonths   = "6M"
        case year        = "1Y"
        case thisMonth   = "MTD"      // Calendar month-to-date
        case lastMonth   = "LAST"     // Previous calendar month
        case thisQuarter = "QTD"
        case ytd         = "YTD"

        var label: String { rawValue }

        /// Inclusive start of the period.
        var startDate: Date {
            let cal = Calendar.current
            let now = Date()
            switch self {
            case .month:        return cal.date(byAdding: .day, value: -30, to: now) ?? now
            case .quarter:      return cal.date(byAdding: .day, value: -90, to: now) ?? now
            case .sixMonths:    return cal.date(byAdding: .day, value: -180, to: now) ?? now
            case .year:         return cal.date(byAdding: .day, value: -365, to: now) ?? now
            case .thisMonth:    return cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            case .lastMonth:
                let firstOfThisMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
                return cal.date(byAdding: .month, value: -1, to: firstOfThisMonth) ?? now
            case .thisQuarter:
                let month = cal.component(.month, from: now)
                let qStartMonth = ((month - 1) / 3) * 3 + 1
                return cal.date(from: DateComponents(year: cal.component(.year, from: now), month: qStartMonth, day: 1)) ?? now
            case .ytd:
                return cal.date(from: DateComponents(year: cal.component(.year, from: now), month: 1, day: 1)) ?? now
            }
        }

        /// Inclusive end of the period (now for trailing windows; first-of-this-month for lastMonth).
        var endDate: Date {
            let cal = Calendar.current
            let now = Date()
            switch self {
            case .lastMonth:
                return cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            default:
                return now
            }
        }

        /// Start of the *prior* equivalent period (used for trend comparisons).
        var priorPeriodStartDate: Date {
            let cal = Calendar.current
            let now = Date()
            switch self {
            case .month:     return cal.date(byAdding: .day, value: -60, to: now) ?? now
            case .quarter:   return cal.date(byAdding: .day, value: -180, to: now) ?? now
            case .sixMonths: return cal.date(byAdding: .day, value: -360, to: now) ?? now
            case .year:      return cal.date(byAdding: .day, value: -730, to: now) ?? now
            case .thisMonth:
                return cal.date(byAdding: .month, value: -1, to: startDate) ?? now
            case .lastMonth:
                return cal.date(byAdding: .month, value: -1, to: startDate) ?? now
            case .thisQuarter:
                return cal.date(byAdding: .month, value: -3, to: startDate) ?? now
            case .ytd:
                return cal.date(from: DateComponents(year: cal.component(.year, from: now) - 1, month: 1, day: 1)) ?? now
            }
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

    // Pipeline stats (only populated when pipeline.view is granted)
    @Published var activeLeadCount: Int = 0
    @Published var weightedForecastValue: Double = 0
    @Published var staleLeadsCount: Int = 0
    @Published var nextFollowUpDue: Date? = nil

    // Breakdown arrays
    @Published var paymentBreakdown: [BreakdownItem] = []
    @Published var expenseBreakdown: [BreakdownItem] = []
    @Published var outstandingInvoiceBreakdown: [BreakdownItem] = []

    // Books Phase 2 — Card 2 (Cash Flow) weekly bucketing
    /// Payments-in bucketed by ISO week start (Monday). Card 2 consumer.
    @Published var paymentsByWeek: [(weekStart: Date, amount: Double)] = []
    /// Expenses-out bucketed by ISO week start. Card 2 consumer.
    @Published var expensesByWeek: [(weekStart: Date, amount: Double)] = []

    // Books Phase 2 — Card 4 (Forecast) per-stage breakdown
    /// Weighted pipeline value broken out per active stage. Card 4 consumer.
    /// `value` is sum(estimatedValue × winProbability) for opportunities in this stage.
    /// `avgProbability` is the unweighted arithmetic mean of `win_probability` across
    /// the same set (Mission Deck Card 4 renders this as the "×62%" stage indicator —
    /// per-opportunity probability, NOT value-weighted).
    struct StageForecast: Identifiable {
        let id: PipelineStage
        /// Backwards-compatible alias for legacy `.stage` consumers.
        var stage: PipelineStage { id }
        let value: Double
        let avgProbability: Double
        let count: Int
    }
    @Published var weightedForecastByStage: [StageForecast] = []

    // Books Phase 2 — Card 5 (Jobs) per-project profitability
    struct JobNet: Identifiable {
        let id: String      // projectId
        let title: String
        let revenue: Double
        let cost: Double
        var net: Double { revenue - cost }
    }
    @Published var topProjectsByNet: [JobNet] = []
    @Published var profitableProjectCount: Int = 0
    @Published var avgProjectMargin: Double = 0
    @Published var losersProjectCount: Int = 0

    // MARK: - Books Phase 3 (Mission Deck) — per-card error tracking

    /// Identifies a card on the Books carousel for fail-soft error + retry routing.
    /// One repository fetch failure populates the affected cards here so siblings
    /// can keep rendering live data.
    enum BooksCard: Hashable {
        case pl, cashFlow, ar, forecast, jobs
    }

    @Published private(set) var failedCards: Set<BooksCard> = []

    func cardError(_ card: BooksCard) -> Bool { failedCards.contains(card) }

    /// Clear the failure flag for `card` and re-run the load. Today `loadData()`
    /// is all-or-nothing (cheap), so we just rerun the whole pull; a future pass
    /// can refetch only the slice this card depends on.
    func retry(_ card: BooksCard) async {
        failedCards.remove(card)
        await loadData()
    }

    // MARK: - Books Phase 3 (Mission Deck) — sync + skeleton coordination

    /// VM-local sync state — drives the `BooksSyncBanner` and skeleton fade-out.
    ///
    /// Note: `BooksSyncBanner.SyncState` is a separate enum (no `.synced` case)
    /// because the banner only renders during non-synced states. Phase F maps
    /// `.synced` to "hide the banner".
    enum SyncState: Equatable {
        case syncing, synced, offline, error
    }

    @Published private(set) var syncState: SyncState = .synced
    @Published private(set) var lastSyncedAt: Date?

    /// `false` until the first fully-successful `loadData()` completes.
    /// Cards render the skeleton path when `!hasEverLoaded && isLoading`.
    /// Once true, subsequent loads happen in-place behind the sync banner.
    @Published private(set) var hasEverLoaded: Bool = false

    // MARK: - Private State

    private var estimateRepository: EstimateRepository?
    private var invoiceRepository: InvoiceRepository?
    private var expenseRepository: ExpenseRepository?
    private var opportunityRepository: OpportunityRepository?
    private var modelContext: ModelContext?
    private var companyId: String?

    // Cached raw data from repositories
    private var allEstimates: [EstimateDTO] = []
    private var allInvoices: [InvoiceDTO] = []
    private var allExpenses: [ExpenseDTO] = []
    private var allOpportunities: [OpportunityDTO] = []
    private var allAllocations: [ExpenseAllocationDTO] = []

    // MARK: - Setup

    /// Initialize repositories and optionally provide a ModelContext for client name lookups.
    func setup(companyId: String, modelContext: ModelContext? = nil) {
        self.companyId = companyId
        self.modelContext = modelContext
        estimateRepository = EstimateRepository(companyId: companyId)
        invoiceRepository = InvoiceRepository(companyId: companyId)
        expenseRepository = ExpenseRepository(companyId: companyId)
        opportunityRepository = OpportunityRepository(companyId: companyId)
    }

    // MARK: - Load & Recalculate

    /// Fetch all financial + pipeline data from Supabase, then compute metrics.
    /// Pipeline opportunities are loaded only when `pipeline.view` is granted.
    ///
    /// Mission Deck Phase 3 behavior:
    ///  * Fail-soft per fetch. A single repo failure routes the affected cards into
    ///    `failedCards` so siblings keep rendering. Successful fetches overwrite
    ///    their caches; failed fetches leave the prior cache intact.
    ///  * `syncState` reflects the worst error encountered: any URLError with
    ///    `.notConnectedToInternet` / `.networkConnectionLost` / `.timedOut`
    ///    downgrades to `.offline`; any other error downgrades to `.error`.
    ///  * `hasEverLoaded` flips true only on a fully-clean load — partial failure
    ///    keeps the skeleton path live so the next attempt still has somewhere
    ///    to land.
    func loadData() async {
        guard estimateRepository != nil,
              invoiceRepository != nil,
              expenseRepository != nil else { return }

        isLoading = true
        syncState = .syncing
        defer { isLoading = false }

        let canSeePipeline = PermissionStore.shared.can("pipeline.view")

        async let estimatesTask = fetchEstimatesResult()
        async let invoicesTask = fetchInvoicesResult()
        async let expensesTask = fetchExpensesResult()
        async let oppsTask: Result<[OpportunityDTO], Error> =
            canSeePipeline ? fetchOpportunitiesResult() : .success([])
        async let allocationsTask = fetchAllocationsResult()

        let (estimatesResult, invoicesResult, expensesResult, oppsResult, allocationsResult) =
            await (estimatesTask, invoicesTask, expensesTask, oppsTask, allocationsTask)

        var newFailedCards: Set<BooksCard> = []
        var sawOffline = false
        var sawHardError = false

        func classify(_ error: Error) {
            if let urlError = error as? URLError,
               [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(urlError.code) {
                sawOffline = true
            } else {
                sawHardError = true
            }
        }

        // Estimates — feed P&L FORECAST tile + Card 4 indirectly. Per spec § 6.3,
        // estimates failure does not map to any card directly (opportunities is the
        // direct feed for the forecast card).
        switch estimatesResult {
        case .success(let v):
            allEstimates = v
        case .failure(let e):
            classify(e)
            print("[MoneyDashboard] Failed to fetch estimates: \(e.localizedDescription)")
        }

        // Invoices — feeds P&L, Cash Flow, A/R, Jobs.
        switch invoicesResult {
        case .success(let v):
            allInvoices = v
        case .failure(let e):
            classify(e)
            print("[MoneyDashboard] Failed to fetch invoices: \(e.localizedDescription)")
            newFailedCards.formUnion([.pl, .cashFlow, .ar, .jobs])
        }

        // Expenses — feeds P&L, Cash Flow, Jobs.
        switch expensesResult {
        case .success(let v):
            allExpenses = v
        case .failure(let e):
            classify(e)
            print("[MoneyDashboard] Failed to fetch expenses: \(e.localizedDescription)")
            newFailedCards.formUnion([.pl, .cashFlow, .jobs])
        }

        // Opportunities — feeds Forecast only.
        switch oppsResult {
        case .success(let v):
            allOpportunities = v
        case .failure(let e):
            classify(e)
            print("[MoneyDashboard] Failed to fetch opportunities: \(e.localizedDescription)")
            newFailedCards.insert(.forecast)
        }

        // Allocations — feeds Jobs (per-project cost split).
        switch allocationsResult {
        case .success(let v):
            allAllocations = v
        case .failure(let e):
            classify(e)
            print("[MoneyDashboard] Failed to fetch allocations: \(e.localizedDescription)")
            newFailedCards.insert(.jobs)
        }

        failedCards = newFailedCards
        recalculate()

        if sawHardError {
            syncState = .error
        } else if sawOffline {
            syncState = .offline
        } else {
            syncState = .synced
            lastSyncedAt = Date()
            if !hasEverLoaded { hasEverLoaded = true }
        }
    }

    /// Recompute all metrics from cached data for the selected period.
    func recalculate() {
        let now = Date()
        let periodStart = selectedPeriod.startDate
        let periodEnd = selectedPeriod.endDate
        let priorStart = selectedPeriod.priorPeriodStartDate

        // ── Invoices in period (by createdAt) ──
        let invoicesInPeriod = allInvoices.filter { dto in
            guard let ca = dto.createdAt, let created = SupabaseDate.parse(ca) else { return false }
            return created >= periodStart && created <= periodEnd && dto.status != InvoiceStatus.void.rawValue
        }
        totalSales = invoicesInPeriod.reduce(0) { $0 + ($1.total ?? 0) }

        // ── Payments in period ──
        let paymentsInPeriod = allInvoices.flatMap { dto -> [PaymentDTO] in
            (dto.payments ?? []).filter { payment in
                guard let dateStr = payment.paymentDate, let paidAt = SupabaseDate.parse(dateStr) else { return false }
                return paidAt >= periodStart && paidAt <= periodEnd && !(payment.isVoid ?? false)
            }
        }
        totalPayments = paymentsInPeriod.reduce(0) { $0 + ($1.amount ?? 0) }

        // ── Expenses in period ──
        let expensesInPeriod = allExpenses.filter { dto in
            guard dto.deletedAt == nil else { return false }
            let dateString = dto.expenseDate ?? dto.createdAt
            guard let date = SupabaseDate.parse(dateString) else { return false }
            return date >= periodStart && date <= periodEnd
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
            let status = InvoiceStatus(rawValue: dto.status ?? "")
            return (dto.balanceDue ?? 0) > 0 && dueDate < now && status != .void
        }
        overdueInvoicesCount = overdueInvoices.count
        overdueInvoicesValue = overdueInvoices.reduce(0) { $0 + ($1.balanceDue ?? 0) }

        // ── Close rate (estimates in period) ──
        let estimatesInPeriod = allEstimates.filter { dto in
            guard let created = SupabaseDate.parse(dto.createdAt) else { return false }
            return created >= periodStart && created <= periodEnd
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

        // ── Pipeline metrics (only meaningful when opps are loaded under pipeline.view) ──
        let activeOpps = allOpportunities.filter { dto in
            let stage = PipelineStage(rawValue: dto.stage)
            let isTerminal = stage?.isTerminal ?? false
            return !isTerminal && dto.deletedAt == nil && dto.archivedAt == nil
        }
        activeLeadCount = activeOpps.count
        weightedForecastValue = activeOpps.reduce(0) { sum, dto in
            let stage = PipelineStage(rawValue: dto.stage) ?? .newLead
            let pct = dto.winProbability ?? stage.winProbability
            let est = dto.estimatedValue ?? 0
            return sum + (est * Double(pct) / 100.0)
        }
        staleLeadsCount = activeOpps.filter { dto in
            guard let stage = PipelineStage(rawValue: dto.stage),
                  let entered = SupabaseDate.parse(dto.stageEnteredAt) else { return false }
            let days = Calendar.current.dateComponents([.day], from: entered, to: now).day ?? 0
            return days > stage.staleThresholdDays
        }.count
        nextFollowUpDue = activeOpps
            .compactMap { $0.nextFollowUpAt.flatMap { SupabaseDate.parse($0) } }
            .filter { $0 >= now }
            .min()

        // ── Books Phase 3 (Mission Deck) — per-stage forecast with probability ──
        // Card 4 renders `value` as the stage-level $ bar and `avgProbability` as
        // the "×62%" indicator. avgProbability is the UNWEIGHTED arithmetic mean
        // of win_probability across opportunities in this stage (NOT value-weighted).
        // Sort by PipelineStage.allCases order so bars render in funnel sequence,
        // not by dollar amount (matches the handoff direction-b layout).
        var weightedSumByStage: [PipelineStage: Double] = [:]
        var probabilitySumByStage: [PipelineStage: Double] = [:]
        var countByStage: [PipelineStage: Int] = [:]
        for dto in activeOpps {
            guard let stage = PipelineStage(rawValue: dto.stage) else { continue }
            let pct = dto.winProbability ?? stage.winProbability
            let est = dto.estimatedValue ?? 0
            weightedSumByStage[stage, default: 0] += est * Double(pct) / 100.0
            probabilitySumByStage[stage, default: 0] += Double(pct)
            countByStage[stage, default: 0] += 1
        }
        weightedForecastByStage = PipelineStage.allCases
            .filter { !$0.isTerminal }
            .compactMap { stage in
                guard let count = countByStage[stage], count > 0 else { return nil }
                let value = weightedSumByStage[stage] ?? 0
                let probSum = probabilitySumByStage[stage] ?? 0
                return StageForecast(
                    id: stage,
                    value: value,
                    avgProbability: probSum / Double(count),
                    count: count
                )
            }

        // ── Books Phase 2 — weekly bucketing for Card 2 (Cash Flow) ──
        paymentsByWeek = bucketByWeek(
            paymentsInPeriod,
            dateOf: { $0.paymentDate.flatMap { SupabaseDate.parse($0) } },
            amountOf: { $0.amount ?? 0 }
        )
        expensesByWeek = bucketByWeek(
            expensesInPeriod,
            dateOf: { SupabaseDate.parse($0.expenseDate ?? $0.createdAt) },
            amountOf: { $0.amount }
        )

        // ── Books Phase 2 — per-project profitability for Card 5 (Jobs) ──
        computeJobNets(periodStart: periodStart, periodEnd: periodEnd)
    }

    // MARK: - Private Helpers

    // Mission Deck Phase 3 — Result-returning fetches.
    // The caller (`loadData()`) classifies errors into offline-vs-hard and
    // routes per-card failure flags. Helpers stay quiet here; the call site
    // owns logging so the failure message is co-located with the card mapping.

    private func fetchEstimatesResult() async -> Result<[EstimateDTO], Error> {
        guard let repo = estimateRepository else { return .success([]) }
        do { return .success(try await repo.fetchAll()) }
        catch { return .failure(error) }
    }

    private func fetchInvoicesResult() async -> Result<[InvoiceDTO], Error> {
        guard let repo = invoiceRepository else { return .success([]) }
        do { return .success(try await repo.fetchAll()) }
        catch { return .failure(error) }
    }

    private func fetchExpensesResult() async -> Result<[ExpenseDTO], Error> {
        guard let repo = expenseRepository else { return .success([]) }
        do { return .success(try await repo.fetchAll()) }
        catch { return .failure(error) }
    }

    private func fetchOpportunitiesResult() async -> Result<[OpportunityDTO], Error> {
        guard let repo = opportunityRepository else { return .success([]) }
        do { return .success(try await repo.fetchAll()) }
        catch { return .failure(error) }
    }

    // MARK: - Avg Days to Payment

    private func computeAvgDaysToPayment(invoicesInPeriod: [InvoiceDTO]) {
        var totalDays: Double = 0
        var count: Int = 0

        for invoice in invoicesInPeriod {
            guard let paidAtStr = invoice.paidAt,
                  let paidAt = SupabaseDate.parse(paidAtStr),
                  let ca = invoice.createdAt, let createdAt = SupabaseDate.parse(ca) else { continue }
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
            let status = InvoiceStatus(rawValue: dto.status ?? "")
            return (dto.balanceDue ?? 0) > 0 && status != .void
        }

        // Sort by balance due descending, take top 3
        let top3 = unpaid
            .sorted { ($0.balanceDue ?? 0) > ($1.balanceDue ?? 0) }
            .prefix(3)

        // Build client name lookup from ModelContext if available
        let clientNames = lookupClientNames(for: top3.compactMap { $0.clientId })

        topUnpaidInvoices = top3.map { dto in
            let clientName: String
            if let cid = dto.clientId, let name = clientNames[cid] {
                clientName = name
            } else {
                clientName = dto.subject ?? dto.invoiceNumber ?? "Invoice"
            }

            var daysOverdue = 0
            if let dueDateStr = dto.dueDate,
               let dueDate = SupabaseDate.parse(dueDateStr),
               dueDate < now {
                daysOverdue = max(0, Calendar.current.dateComponents([.day], from: dueDate, to: now).day ?? 0)
            }

            return (clientName: clientName, amount: dto.balanceDue ?? 0, daysOverdue: daysOverdue)
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
            .sorted { $0.paymentDate.flatMap { SupabaseDate.parse($0) } ?? Date.distantPast > $1.paymentDate.flatMap { SupabaseDate.parse($0) } ?? Date.distantPast }
            .map { payment in
                let method = payment.paymentMethod.flatMap { PaymentMethod(rawValue: $0)?.displayName } ?? payment.paymentMethod?.uppercased() ?? "OTHER"
                let invoiceNum = invoiceNumber(for: payment.invoiceId ?? "")
                let label = "\(invoiceNum) — \(method)"
                return BreakdownItem(
                    label: label,
                    amount: payment.amount ?? 0,
                    date: payment.paymentDate.flatMap { SupabaseDate.parse($0) },
                    entityId: payment.invoiceId ?? "",
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
            let status = InvoiceStatus(rawValue: dto.status ?? "")
            return (dto.balanceDue ?? 0) > 0 && status != .void
        }
        .sorted { ($0.balanceDue ?? 0) > ($1.balanceDue ?? 0) }

        let clientNames = lookupClientNames(for: outstanding.compactMap { $0.clientId })

        outstandingInvoiceBreakdown = outstanding.map { dto in
            let label: String
            if let cid = dto.clientId, let name = clientNames[cid] {
                label = "\(name) — \(dto.invoiceNumber ?? "Invoice")"
            } else {
                label = dto.subject ?? dto.invoiceNumber ?? "Invoice"
            }

            return BreakdownItem(
                label: label,
                amount: dto.balanceDue ?? 0,
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

    // MARK: - Books Phase 2 — Helpers (weekly buckets, job nets, allocations)

    private func fetchAllocationsResult() async -> Result<[ExpenseAllocationDTO], Error> {
        guard let repo = expenseRepository else { return .success([]) }
        do { return .success(try await repo.fetchAllAllocations()) }
        catch { return .failure(error) }
    }

    private func weekStart(for date: Date) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2 // Monday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? date
    }

    private func bucketByWeek<T>(_ items: [T], dateOf: (T) -> Date?, amountOf: (T) -> Double) -> [(weekStart: Date, amount: Double)] {
        var buckets: [Date: Double] = [:]
        for item in items {
            guard let d = dateOf(item) else { continue }
            let ws = weekStart(for: d)
            buckets[ws, default: 0] += amountOf(item)
        }
        return buckets.sorted { $0.key < $1.key }.map { (weekStart: $0.key, amount: $0.value) }
    }

    /// Suppress refund / rounding noise from the worst-loser displacement rule.
    /// A project losing less than $500 isn't worth bumping a winner off the
    /// top-5 display slice; aggregates below count every loss regardless.
    private let worstLossFloor: Double = -500.0

    private func computeJobNets(periodStart: Date, periodEnd: Date) {
        // Revenue per project: sum of voided-excluded payments tied to invoices with a projectId, paid in-period.
        var revenuePerProject: [String: Double] = [:]
        for inv in allInvoices {
            guard let pid = inv.projectId,
                  inv.deletedAt == nil,
                  inv.status != InvoiceStatus.void.rawValue else { continue }
            for payment in inv.payments ?? [] {
                guard let dStr = payment.paymentDate,
                      let d = SupabaseDate.parse(dStr),
                      d >= periodStart, d <= periodEnd,
                      !(payment.isVoid ?? false) else { continue }
                revenuePerProject[pid, default: 0] += payment.amount ?? 0
            }
        }

        // Cost per project: sum of allocation.amount (or expense.amount * pct/100) for non-deleted expenses in period.
        var costPerProject: [String: Double] = [:]
        let expenseById = Dictionary(uniqueKeysWithValues: allExpenses.map { ($0.id, $0) })
        for alloc in allAllocations {
            guard let expense = expenseById[alloc.expenseId],
                  expense.deletedAt == nil else { continue }
            let dateStr = expense.expenseDate ?? expense.createdAt
            guard let d = SupabaseDate.parse(dateStr), d >= periodStart, d <= periodEnd else { continue }
            let amount = alloc.amount ?? (expense.amount * alloc.percentage / 100.0)
            costPerProject[alloc.projectId, default: 0] += amount
        }

        let projectIds = Array(Set(revenuePerProject.keys).union(costPerProject.keys))
        let projectTitles = projectTitleLookup(for: projectIds)

        let allNets: [JobNet] = projectIds.map { pid in
            JobNet(
                id: pid,
                title: projectTitles[pid] ?? "Untitled",
                revenue: revenuePerProject[pid] ?? 0,
                cost: costPerProject[pid] ?? 0
            )
        }

        // Display slice: top 5 by net descending, then displace the bottom with
        // the period's worst loser (if it isn't already in the top 5 AND its
        // loss exceeds the noise floor). Card 5 shows "which jobs made me
        // money" — surfacing the worst loser even on a strong month preserves
        // the early-warning channel for losses (decision Q2).
        var result = Array(allNets.sorted { $0.net > $1.net }.prefix(5))

        if let worstLoser = allNets
            .filter({ $0.net < worstLossFloor })
            .min(by: { $0.net < $1.net }),
           !result.contains(where: { $0.id == worstLoser.id })
        {
            if !result.isEmpty { result.removeLast() }
            result.append(worstLoser)
        }
        topProjectsByNet = result

        // Aggregates count the FULL set, not the display slice.
        profitableProjectCount = allNets.filter { $0.net > 0 }.count
        losersProjectCount = allNets.filter { $0.net < 0 }.count
        let withRevenue = allNets.filter { $0.revenue > 0 }
        avgProjectMargin = withRevenue.isEmpty
            ? 0
            : withRevenue.map { $0.net / $0.revenue }.reduce(0, +) / Double(withRevenue.count)
    }

    private func projectTitleLookup(for projectIds: [String]) -> [String: String] {
        guard let context = modelContext, !projectIds.isEmpty else { return [:] }
        var result: [String: String] = [:]
        do {
            let descriptor = FetchDescriptor<Project>()
            let allProjects = try context.fetch(descriptor)
            for p in allProjects where projectIds.contains(p.id) {
                result[p.id] = p.title
            }
        } catch {
            print("[MoneyDashboard] Failed to fetch projects: \(error.localizedDescription)")
        }
        return result
    }
}
