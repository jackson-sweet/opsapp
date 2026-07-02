//
//  BooksTabView.swift
//  OPS
//
//  Books money command center.
//  Money & Leads redesign (2026-06-30) — design direction "1b · COMMAND GRID".
//  Top: AppHeader + sync banner + period pill + a scannable KPI command grid
//  (NET CASH hero · CASH FLOW · RUNWAY · RECEIVABLES · FORECAST · JOB MARGIN),
//  each tile drilling into the existing expand sheet / RUNWAY full screen.
//  Below: a sticky ledger band (Invoices · Estimates · Expenses + filter chips)
//  over flat, hairline-separated rows. Pipeline has its own top-level tab.
//

import SwiftUI

struct BooksTabView: View {
    @StateObject private var dashboardVM: MoneyDashboardViewModel
    @StateObject private var estimateVM = EstimateViewModel()
    @StateObject private var invoiceVM = InvoiceViewModel()
    @StateObject private var expenseVM = ExpenseViewModel()
    @StateObject private var cashflowVM = CashflowForecastViewModel()

    init() {
        _dashboardVM = StateObject(wrappedValue: MoneyDashboardViewModel())
    }

    #if DEBUG
    /// Preview-only — injects a pre-seeded dashboard VM so the command grid
    /// renders with realistic data on Xcode's preview canvas. Bypasses the
    /// usual setup() / loadData() chain (which is guarded by `currentUser`).
    init(previewDashboardVM: MoneyDashboardViewModel) {
        _dashboardVM = StateObject(wrappedValue: previewDashboardVM)
    }
    #endif

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Active segment persisted across sessions and visible to FloatingActionMenu.
    @AppStorage("books.selectedSegment") private var selectedSegmentRaw: String = BooksSection.invoices.rawValue

    // Books owns the ledger filter state so the chip SETS can match the design
    // (estimates ALL · OUT · WON here) independent of each list's standalone VM.
    @State private var invoiceFilter: BooksInvoiceFilter = .all
    @State private var estimateFilter: BooksEstimateFilter = .all
    @State private var expenseFilter: BooksExpenseFilter = .all

    @State private var expandedCard: HeroCarousel.CardID?
    @State private var showCashflowForecast = false
    @State private var showBatchReview = false

    // Ledger detail-push selection is held here (not in BooksLedger) so the
    // navigationDestination modifiers can sit outside the ScrollView's
    // LazyVStack — a navigationDestination inside a lazy container is ignored.
    @State private var selectedInvoice: Invoice?
    @State private var selectedEstimate: Estimate?

    // MARK: - Derived state

    private var selectedSegment: BooksSection {
        BooksSection(rawValue: selectedSegmentRaw) ?? .invoices
    }

    private var visibleSegments: [BooksSection] {
        BooksSection.allCases.filter { permissionStore.can($0.requiredPermission) }
    }

    private var canFinances: Bool { permissionStore.can("finances.view") }
    private var canPipeline: Bool { permissionStore.can("pipeline.view") }
    private var hasFinances: Bool { canFinances }
    private var gridVisible: Bool { canFinances || canPipeline }

    /// Approvers get the one-tap path from Money into the batch-review hub —
    /// same `expenses.approve` gate as the Settings entry.
    private var canReviewBatches: Bool { permissionStore.can("expenses.approve") }

    /// Envelopes waiting on the approver (pending / submitted; a filling
    /// envelope is never review-ready). Same predicate as the hub's
    /// NEEDS REVIEW tab, computed off the batches the Books VM already loads.
    private var batchesNeedingReview: Int {
        expenseVM.batches.filter { ExpenseBatchStatus(rawValue: $0.status)?.needsReview == true }.count
    }

    /// Maps the dashboard VM's 4-case sync state onto `BooksSyncBanner`'s
    /// 3-case enum. `.synced` returns nil — banner hides when fully synced.
    private var bannerState: BooksSyncBanner.SyncState? {
        switch dashboardVM.syncState {
        case .syncing: return .syncing
        case .offline: return .offline
        case .error:   return .error
        case .synced:  return nil
        }
    }

    private var ledgerLabel: String {
        switch selectedSegment {
        case .invoices:  return "WHO OWES YOU"
        case .estimates: return "OUT & WON"
        case .expenses:  return "SPEND LOG"
        }
    }

    private var currentChips: [TacticalChip] {
        switch selectedSegment {
        case .invoices:  return BooksInvoiceFilter.chips(from: invoiceVM.invoices)
        case .estimates: return BooksEstimateFilter.chips(from: estimateVM.estimates)
        case .expenses:  return BooksExpenseFilter.chips(from: expenseVM.expenses)
        }
    }

    private var currentCount: Int {
        switch selectedSegment {
        case .invoices:  return invoiceVM.invoices.filter(invoiceFilter.matches).count
        case .estimates: return estimateVM.estimates.filter(estimateFilter.matches).count
        case .expenses:  return expenseVM.expenses.filter(expenseFilter.matches).count
        }
    }

    private var segmentBinding: Binding<BooksSection> {
        Binding(
            get: { selectedSegment },
            set: { selectedSegmentRaw = $0.rawValue }
        )
    }

    private var filterBinding: Binding<String> {
        switch selectedSegment {
        case .invoices:
            return Binding(get: { invoiceFilter.rawValue },
                           set: { invoiceFilter = BooksInvoiceFilter(rawValue: $0) ?? .all })
        case .estimates:
            return Binding(get: { estimateFilter.rawValue },
                           set: { estimateFilter = BooksEstimateFilter(rawValue: $0) ?? .all })
        case .expenses:
            return Binding(get: { expenseFilter.rawValue },
                           set: { expenseFilter = BooksExpenseFilter(rawValue: $0) ?? .all })
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppHeader(headerType: .books)
                    .padding(.bottom, OPSStyle.Layout.spacing2)

                if let state = bannerState {
                    BooksSyncBanner(
                        lastSyncedAt: dashboardVM.lastSyncedAt,
                        state: state,
                        onRetry: state != .syncing ? { Task { await refreshAll() } } : nil
                    )
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.bottom, OPSStyle.Layout.spacing2)
                    .transition(.opacity)
                }

                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        if gridVisible {
                            if canFinances {
                                HStack {
                                    PeriodPill(selected: $dashboardVM.selectedPeriod)
                                    Spacer()
                                }
                                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                                .padding(.top, OPSStyle.Layout.spacing1)
                                .padding(.bottom, OPSStyle.Layout.spacing2_5)
                            }

                            BooksCommandGrid(
                                viewModel: dashboardVM,
                                cashflowVM: cashflowVM,
                                canFinances: canFinances,
                                canPipeline: canPipeline,
                                onExpand: { card in expandedCard = card },
                                onOpenRunway: { showCashflowForecast = true }
                            )
                            .padding(.bottom, OPSStyle.Layout.spacing3)
                        }

                        if !visibleSegments.isEmpty {
                            Section {
                                BooksLedger(
                                    segment: selectedSegment,
                                    invoiceVM: invoiceVM,
                                    estimateVM: estimateVM,
                                    expenseVM: expenseVM,
                                    invoiceFilter: invoiceFilter,
                                    estimateFilter: estimateFilter,
                                    expenseFilter: expenseFilter,
                                    selectedInvoice: $selectedInvoice,
                                    selectedEstimate: $selectedEstimate
                                )
                                .padding(.top, OPSStyle.Layout.spacing2)
                            } header: {
                                ledgerBand
                            }
                        }
                    }
                }
                .refreshable { await refreshAll() }
                // Clear the 100pt CustomTabBar overlay so the last row isn't
                // hidden behind it — matches the app's primary-tab convention.
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 120)
                }
            }
            .animation(reduceMotion ? nil : OPSStyle.Animation.panel, value: dashboardVM.syncState)
            .animation(reduceMotion ? nil : OPSStyle.Animation.panel, value: selectedSegmentRaw)
            .animation(reduceMotion ? nil : OPSStyle.Animation.panel, value: invoiceFilter)
            .animation(reduceMotion ? nil : OPSStyle.Animation.panel, value: estimateFilter)
            .animation(reduceMotion ? nil : OPSStyle.Animation.panel, value: expenseFilter)
            .background(OPSStyle.Colors.background.ignoresSafeArea())
            .sheet(item: $expandedCard) { card in
                ExpandedCardSheet(
                    card: card,
                    viewModel: dashboardVM,
                    onDrillOutstanding: {
                        selectedSegmentRaw = BooksSection.invoices.rawValue
                        invoiceFilter = .overdue
                    },
                    onDrillForecast: {
                        selectedSegmentRaw = BooksSection.estimates.rawValue
                        estimateFilter = .out
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $showCashflowForecast) {
                CashflowForecastScreen(viewModel: cashflowVM)
            }
            .navigationDestination(isPresented: $showBatchReview) {
                ExpensesListView()
            }
            // Ledger detail pushes — placed OUTSIDE the ScrollView's LazyVStack
            // (a navigationDestination inside a lazy container is ignored by the
            // nav stack). A row tap sets these bindings inside BooksLedger.
            .navigationDestination(item: $selectedInvoice) { invoice in
                InvoiceDetailView(invoice: invoice, viewModel: invoiceVM)
            }
            .navigationDestination(item: $selectedEstimate) { estimate in
                EstimateDetailView(estimate: estimate, viewModel: estimateVM)
            }
        }
        .trackScreen("Books")
        .task {
            setupViewModels()
            await refreshAll()
            if !visibleSegments.contains(selectedSegment), let first = visibleSegments.first {
                selectedSegmentRaw = first.rawValue
            }
        }
        // Segment routing from notification rail / push deep links.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BooksSelectSegment"))) { notification in
            guard let raw = notification.userInfo?["segment"] as? String,
                  let segment = BooksSection(rawValue: raw),
                  visibleSegments.contains(segment) else { return }
            withAnimation(reduceMotion ? nil : OPSStyle.Animation.panel) {
                selectedSegmentRaw = segment.rawValue
            }
        }
        .onChange(of: visibleSegments.map(\.rawValue).joined(separator: "|")) { _, _ in
            guard !visibleSegments.contains(selectedSegment), let first = visibleSegments.first else { return }
            withAnimation(reduceMotion ? nil : OPSStyle.Animation.panel) {
                selectedSegmentRaw = first.rawValue
            }
        }
        // Cashflow forecast deep-link from notification rail.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenCashflowForecast"))) { _ in
            guard hasFinances else { return }
            showCashflowForecast = true
        }
    }

    // MARK: - Pinned ledger band (segments + chips + section marker)

    private var ledgerBand: some View {
        VStack(spacing: 0) {
            BooksLedgerSegments(segments: visibleSegments, selected: segmentBinding)
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.top, OPSStyle.Layout.spacing2_5)

            TacticalChipRow(chips: currentChips, selectedId: filterBinding)
                .padding(.top, OPSStyle.Layout.spacing2_5)

            ledgerMarker
                .padding(.top, OPSStyle.Layout.spacing2_5)
                .padding(.bottom, OPSStyle.Layout.spacing2)

            Rectangle()
                .fill(OPSStyle.Colors.line)
                .frame(height: 1)
        }
        .background(OPSStyle.Colors.background)
    }

    private var ledgerMarker: some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            Text("//").foregroundColor(OPSStyle.Colors.textMute)
            Text(ledgerLabel).foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("·").foregroundColor(OPSStyle.Colors.textMute)
            Text("\(currentCount)").foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
            if selectedSegment == .expenses && canReviewBatches {
                BooksReviewBatchesLink(count: batchesNeedingReview) {
                    showBatchReview = true
                }
            }
        }
        .font(.custom("JetBrainsMono-Medium", size: 10))
        .tracking(1.6)
        .textCase(.uppercase)
        .monospacedDigit()
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    // MARK: - Setup + load

    private func setupViewModels() {
        guard let companyId = dataController.currentUser?.companyId, !companyId.isEmpty else { return }
        dashboardVM.setup(companyId: companyId, modelContext: modelContext)
        estimateVM.setup(companyId: companyId, modelContext: modelContext)
        invoiceVM.setup(companyId: companyId, modelContext: modelContext)
        expenseVM.setup(
            companyId: companyId,
            currentUserId: dataController.currentUser?.id,
            currentUserName: dataController.currentUser?.fullName
        )
        cashflowVM.setup(companyId: companyId, dashboardVM: dashboardVM)
    }

    /// Refreshes the dashboard first (above the fold), then the three ledgers in
    /// parallel, then the runway forecast. Drives both `.task` and pull-to-refresh.
    private func refreshAll() async {
        await dashboardVM.loadData()
        async let invoices: Void = invoiceVM.loadInvoices()
        async let estimates: Void = estimateVM.loadEstimates()
        async let expenses: Void = expenseVM.loadAll()
        _ = await (invoices, estimates, expenses)
        if canFinances {
            await cashflowVM.load()
        }
    }
}

#if DEBUG
#Preview("BooksTabView — Owner (seeded)") {
    BooksTabView(previewDashboardVM: .previewStub())
        .environmentObject(DataController())
        .environmentObject(PermissionStore.previewOwner())
        .environmentObject(AppState())
        .environmentObject(SubscriptionManager.shared)
        .preferredColorScheme(.dark)
}

#Preview("BooksTabView — Operator (forecast only)") {
    BooksTabView(previewDashboardVM: .previewEmpty())
        .environmentObject(DataController())
        .environmentObject(PermissionStore.previewOperator())
        .environmentObject(AppState())
        .environmentObject(SubscriptionManager.shared)
        .preferredColorScheme(.dark)
}
#endif
