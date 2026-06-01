//
//  BooksTabView.swift
//  OPS
//
//  Books Phase 2 (2026-05-11) — money command center.
//  Mission Deck visual rebuild (2026-05-19) — sync banner, drill filter
//  chip, inset-pill segments, half-sheet A/R detents, pull-to-refresh.
//  Top: AppHeader + sync banner + swipeable 5-card HeroCarousel.
//  Below: 3-segment inset-pill control (Invoices · Estimates · Expenses).
//  Pipeline has moved to its own top-level tab (see `PIPELINE TAB - P1-1`).
//

import SwiftUI

private struct HeaderBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

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
    /// Preview-only — injects a pre-seeded dashboard VM so the carousel
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
    @AppStorage("books.lastViewedCard") private var lastViewedCardRaw: String = HeroCarousel.CardID.pl.rawValue

    @State private var headerCollapsed = false
    @State private var showARDetail = false
    @State private var showCashflowForecast = false

    private var selectedSegment: BooksSection {
        BooksSection(rawValue: selectedSegmentRaw) ?? .invoices
    }

    private var visibleSegments: [BooksSection] {
        BooksSection.allCases.filter { permissionStore.can($0.requiredPermission) }
    }

    /// Convenience gate for the Cashflow Forecast surfaces (preview card +
    /// notification deep link). Same permission the Books-segment finances
    /// section checks.
    private var hasFinances: Bool { permissionStore.can("finances.view") }

    private var carouselVisible: Bool {
        permissionStore.can("finances.view") || permissionStore.can("pipeline.view")
    }

    private var visibleCarouselCards: [HeroCarousel.CardID] {
        HeroCarousel.CardID.allCases.filter { permissionStore.can($0.permission) }
    }

    private var activeCarouselCard: HeroCarousel.CardID {
        let restored = HeroCarousel.CardID(rawValue: lastViewedCardRaw) ?? .pl
        return visibleCarouselCards.contains(restored) ? restored : (visibleCarouselCards.first ?? .pl)
    }

    private var expensesScopeIsOwn: Bool {
        permissionStore.can("expenses.view") && !permissionStore.hasFullAccess("expenses.view")
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

    /// Drill filter chip — shown below the segmented control when a carousel
    /// drill applied an invoice/estimate filter. Tapping × clears the filter.
    /// `.expenses` has no drill-driven filter today, so it is omitted.
    @ViewBuilder
    private var activeFilterChip: some View {
        if selectedSegment == .invoices, invoiceVM.selectedFilter == .overdue {
            BooksDrillFilterChip(label: "OVERDUE", onClear: {
                withAnimation(reduceMotion ? nil : OPSStyle.Animation.panel) {
                    invoiceVM.selectedFilter = .all
                }
            })
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.top, OPSStyle.Layout.spacing2)
            .transition(.opacity)
        } else if selectedSegment == .estimates, estimateVM.selectedFilter == .sent {
            BooksDrillFilterChip(label: "SENT", onClear: {
                withAnimation(reduceMotion ? nil : OPSStyle.Animation.panel) {
                    estimateVM.selectedFilter = .all
                }
            })
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.top, OPSStyle.Layout.spacing2)
            .transition(.opacity)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppHeader(headerType: .books)
                    .padding(.bottom, 8)

                // Sync banner — sits above the hero whenever a sync is in
                // flight, the network is unreachable, or the last fetch
                // hard-failed. Hidden entirely once fully synced.
                if let state = bannerState {
                    BooksSyncBanner(
                        lastSyncedAt: dashboardVM.lastSyncedAt,
                        state: state,
                        onRetry: state != .syncing
                            ? { Task { await dashboardVM.loadData() } }
                            : nil
                    )
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.top, OPSStyle.Layout.spacing2)
                    .transition(.opacity)
                }

                if headerCollapsed && carouselVisible {
                    CollapsedCarouselStrip(
                        viewModel: dashboardVM,
                        activeCard: activeCarouselCard,
                        visibleCards: visibleCarouselCards
                    )
                    .transition(.opacity)
                }

                if headerCollapsed && !visibleSegments.isEmpty {
                    VStack(spacing: 0) {
                        insetPillSegmentedControl
                        activeFilterChip
                    }
                    .background(OPSStyle.Colors.background)
                    .transition(.opacity)
                }

                ScrollView {
                    VStack(spacing: 0) {
                        // Hero carousel — borderless, top-level data.
                        // PeriodPill lives inline on each card's top row (inside HeroCarousel).
                        // Operator role lands here with zero permitted cards and skips the hero.
                        if carouselVisible {
                            HeroCarousel(
                                viewModel: dashboardVM,
                                onDrillOutstanding: {
                                    selectedSegmentRaw = BooksSection.invoices.rawValue
                                    invoiceVM.selectedFilter = .overdue
                                },
                                onDrillForecast: {
                                    selectedSegmentRaw = BooksSection.estimates.rawValue
                                    estimateVM.selectedFilter = .sent
                                },
                                onDrillTopChase: { showARDetail = true },
                            )
                            .environmentObject(permissionStore)
                            .padding(.bottom, OPSStyle.Layout.spacing2)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: HeaderBottomKey.self,
                                        value: geo.frame(in: .named("scroll")).maxY
                                    )
                                }
                            )
                        }

                        // Cashflow forecast preview card — gated on finances.view.
                        // Sits below the dashboard header until the Books carousel
                        // reconstruction lands (see spec §13 coordination notes).
                        if hasFinances {
                            CashflowForecastCard(viewModel: cashflowVM)
                                .padding(.horizontal, OPSStyle.Layout.spacing3)
                                .padding(.top, OPSStyle.Layout.spacing2)
                        }

                        if !headerCollapsed && !visibleSegments.isEmpty {
                            insetPillSegmentedControl
                            activeFilterChip
                        }

                        contentForSegment
                    }
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(HeaderBottomKey.self) { bottomY in
                    let shouldCollapse = bottomY < 0
                    if shouldCollapse != headerCollapsed {
                        withAnimation(reduceMotion ? nil : OPSStyle.Animation.panel) {
                            headerCollapsed = shouldCollapse
                        }
                    }
                }
                // Pull-to-refresh — native SwiftUI PTR. The Mission Deck
                // BooksPTRIndicator (custom OPS-mark + spin arc) is a
                // standalone visual component, not a ProgressViewStyle, so it
                // cannot drive the system refresh control. Native .refreshable
                // is the canonical pattern: it ties into the sync-state flow
                // and inherits all accessibility behavior for free. The custom
                // indicator is deferred to a future polish phase (spec § 7.5).
                .refreshable {
                    await dashboardVM.loadData()
                }
            }
            // Fade the sync banner / drill filter chip in and out on the
            // canonical OPS easing curve when the underlying state flips.
            .animation(reduceMotion ? nil : OPSStyle.Animation.panel, value: dashboardVM.syncState)
            .animation(reduceMotion ? nil : OPSStyle.Animation.panel, value: invoiceVM.selectedFilter)
            .animation(reduceMotion ? nil : OPSStyle.Animation.panel, value: estimateVM.selectedFilter)
            .background(OPSStyle.Colors.background.ignoresSafeArea())
            .sheet(isPresented: $showARDetail) {
                ARAgingDetailView()
                    .environmentObject(dataController)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $showCashflowForecast) {
                CashflowForecastScreen(viewModel: cashflowVM)
            }
        }
        .trackScreen("Books")
        .task {
            setupViewModels()
            await dashboardVM.loadData()
            // If the persisted segment is no longer permitted, snap to first visible.
            if !visibleSegments.contains(selectedSegment), let first = visibleSegments.first {
                selectedSegmentRaw = first.rawValue
            }
        }
        // Bug 8ed0d2ed — segment routing from notification rail / push deep links.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BooksSelectSegment"))) { notification in
            guard let raw = notification.userInfo?["segment"] as? String,
                  let segment = BooksSection(rawValue: raw),
                  visibleSegments.contains(segment) else { return }
            withAnimation(reduceMotion ? nil : OPSStyle.Animation.panel) {
                selectedSegmentRaw = segment.rawValue
            }
        }
        .onChange(of: carouselVisible) { _, isVisible in
            guard !isVisible, headerCollapsed else { return }
            withAnimation(reduceMotion ? nil : OPSStyle.Animation.panel) {
                headerCollapsed = false
            }
        }
        .onChange(of: visibleSegments.map(\.rawValue).joined(separator: "|")) { _, _ in
            guard !visibleSegments.contains(selectedSegment), let first = visibleSegments.first else { return }
            withAnimation(reduceMotion ? nil : OPSStyle.Animation.panel) {
                selectedSegmentRaw = first.rawValue
            }
        }
        // Cashflow forecast deep-link from notification rail. Presents the
        // full forecast screen on top of the Books surface.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenCashflowForecast"))) { _ in
            guard hasFinances else { return }
            showCashflowForecast = true
        }
    }

    // MARK: - Segmented control

    /// Mission Deck inset-pill style (spec § 7.3 / D7).
    /// Neutral fill on active — no accent color (OPS rule "no accent on toggles").
    /// Active pill uses white@0.10 fill + 1pt white@0.22 border + 1pt inset top-light.
    private var insetPillSegmentedControl: some View {
        HStack(spacing: 2) {
            ForEach(visibleSegments) { segment in
                let isActive = selectedSegment == segment
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(reduceMotion ? nil : OPSStyle.Animation.panel) {
                        selectedSegmentRaw = segment.rawValue
                    }
                } label: {
                    Text(segment.rawValue)
                        .font(.custom("JetBrainsMono-Medium", size: 10.5))
                        .tracking(1.68)  // 0.16em at 10.5pt
                        .textCase(.uppercase)
                        .foregroundColor(
                            isActive
                                ? OPSStyle.Colors.primaryText
                                : OPSStyle.Colors.tertiaryText
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(segmentBackground(isActive: isActive))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(segment.rawValue) segment, currently \(isActive ? "selected" : "not selected")")
                .accessibilityHint("Double-tap to view \(segment.rawValue)")
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .strokeBorder(OPSStyle.Colors.lineSoft, lineWidth: 1)
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    @ViewBuilder
    private func segmentBackground(isActive: Bool) -> some View {
        if isActive {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.10))
                // 1pt inset top-light — recessed/embossed effect (spec § 7.3)
                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 1)
                    .padding(.horizontal, 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            )
        } else {
            Color.clear
        }
    }

    // MARK: - Content per segment

    @ViewBuilder
    private var contentForSegment: some View {
        Group {
            switch selectedSegment {
            case .invoices:
                if visibleSegments.contains(.invoices) {
                    InvoicesListView(embedded: true, viewModel: invoiceVM)
                }
            case .estimates:
                if visibleSegments.contains(.estimates) {
                    EstimatesListView(embedded: true, viewModel: estimateVM)
                }
            case .expenses:
                if visibleSegments.contains(.expenses) {
                    if expensesScopeIsOwn {
                        MyExpensesView()
                    } else {
                        ExpensesListView(embedded: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : OPSStyle.Animation.panel, value: selectedSegment)
    }

    // MARK: - Setup

    private func setupViewModels() {
        guard let companyId = dataController.currentUser?.companyId, !companyId.isEmpty else { return }
        dashboardVM.setup(companyId: companyId, modelContext: modelContext)
        estimateVM.setup(companyId: companyId, modelContext: modelContext)
        invoiceVM.setup(companyId: companyId, modelContext: modelContext)
        expenseVM.setup(companyId: companyId)
        cashflowVM.setup(companyId: companyId, dashboardVM: dashboardVM)
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

#Preview("BooksTabView — Operator (no carousel)") {
    BooksTabView(previewDashboardVM: .previewEmpty())
        .environmentObject(DataController())
        .environmentObject(PermissionStore.previewOperator())
        .environmentObject(AppState())
        .environmentObject(SubscriptionManager.shared)
        .preferredColorScheme(.dark)
}
#endif
