//
//  BooksTabView.swift
//  OPS
//
//  Books Phase 2 (2026-05-11) — money command center.
//  Top: AppHeader + PeriodPill + swipeable 5-card HeroCarousel.
//  Below: 3-segment underline control (Invoices · Estimates · Expenses).
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

    // Active segment persisted across sessions and visible to FloatingActionMenu.
    @AppStorage("books.selectedSegment") private var selectedSegmentRaw: String = BooksSection.invoices.rawValue
    @AppStorage("books.lastViewedCard") private var lastViewedCardRaw: String = HeroCarousel.CardID.pl.rawValue

    @State private var headerCollapsed = false
    @State private var showARDetail = false

    private var selectedSegment: BooksSection {
        BooksSection(rawValue: selectedSegmentRaw) ?? .invoices
    }

    private var visibleSegments: [BooksSection] {
        BooksSection.allCases.filter { permissionStore.can($0.requiredPermission) }
    }

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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppHeader(headerType: .books)
                    .padding(.bottom, 8)

                if headerCollapsed && carouselVisible {
                    CollapsedCarouselStrip(
                        viewModel: dashboardVM,
                        activeCard: activeCarouselCard,
                        visibleCards: visibleCarouselCards
                    )
                    .transition(.opacity)
                }

                if headerCollapsed {
                    underlineSegmentedControl
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
                                onDrillCashFlowDays: { /* Cash-flow report — deferred per spec §10 */ },
                                onDrillTopChase: { showARDetail = true },
                                onDrillCloseRate: { /* Pipeline tab drill — see PIPELINE TAB - P1-1 */ },
                                onDrillStale: { /* Pipeline tab drill — see PIPELINE TAB - P1-1 */ },
                                onDrillProfitable: { /* Jobs report — deferred per spec §10 */ },
                                onDrillLosers: { /* Jobs report — deferred per spec §10 */ }
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

                        if !headerCollapsed {
                            underlineSegmentedControl
                        }

                        contentForSegment
                    }
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(HeaderBottomKey.self) { bottomY in
                    let shouldCollapse = bottomY < 0
                    if shouldCollapse != headerCollapsed {
                        withAnimation(OPSStyle.Animation.fast) {
                            headerCollapsed = shouldCollapse
                        }
                    }
                }
            }
            .background(OPSStyle.Colors.background.ignoresSafeArea())
            .sheet(isPresented: $showARDetail) {
                ARAgingDetailView()
                    .environmentObject(dataController)
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
            withAnimation(OPSStyle.Animation.fast) {
                selectedSegmentRaw = segment.rawValue
            }
        }
    }

    // MARK: - Segmented control

    private var underlineSegmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(visibleSegments) { segment in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(OPSStyle.Animation.fast) {
                        selectedSegmentRaw = segment.rawValue
                    }
                } label: {
                    VStack(spacing: OPSStyle.Layout.spacing2) {
                        Text(segment.rawValue)
                            .font(OPSStyle.Typography.sectionLabel)
                            .foregroundColor(
                                selectedSegment == segment
                                    ? OPSStyle.Colors.primaryText
                                    : OPSStyle.Colors.secondaryText
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.top, OPSStyle.Layout.spacing2_5)

                        Rectangle()
                            .frame(height: OPSStyle.Layout.Border.thick)
                            .foregroundColor(
                                selectedSegment == segment
                                    ? OPSStyle.Colors.primaryAccent
                                    : Color.clear
                            )
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - Content per segment

    @ViewBuilder
    private var contentForSegment: some View {
        Group {
            switch selectedSegment {
            case .invoices:
                InvoicesListView(embedded: true)
            case .estimates:
                EstimatesListView(embedded: true)
            case .expenses:
                if expensesScopeIsOwn {
                    MyExpensesView()
                } else {
                    ExpensesListView(embedded: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(OPSStyle.Animation.fast, value: selectedSegment)
    }

    // MARK: - Setup

    private func setupViewModels() {
        guard let companyId = dataController.currentUser?.companyId, !companyId.isEmpty else { return }
        dashboardVM.setup(companyId: companyId, modelContext: modelContext)
        estimateVM.setup(companyId: companyId, modelContext: modelContext)
        invoiceVM.setup(companyId: companyId, modelContext: modelContext)
        expenseVM.setup(companyId: companyId)
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
