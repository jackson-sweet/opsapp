//
//  BooksTabView.swift
//  OPS
//
//  Hub container for BOOKS tab. Replaces MoneyTabView.
//  Top: AppHeader + MoneyDashboardHeader (collapsible).
//  Below: 4-segment underline control (Pipeline · Estimates · Invoices · Expenses).
//  Routes to existing list views for the latter three; new PipelineSectionView for the first.
//

import SwiftUI

private struct HeaderBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct BooksTabView: View {
    @StateObject private var dashboardVM = MoneyDashboardViewModel()
    @StateObject private var estimateVM = EstimateViewModel()
    @StateObject private var invoiceVM = InvoiceViewModel()
    @StateObject private var expenseVM = ExpenseViewModel()

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext

    // Active segment persisted across sessions and visible to FloatingActionMenu.
    @AppStorage("books.selectedSegment") private var selectedSegmentRaw: String = BooksSection.pipeline.rawValue

    @State private var headerCollapsed = false
    @State private var showARDetail = false

    private var selectedSegment: BooksSection {
        BooksSection(rawValue: selectedSegmentRaw) ?? .pipeline
    }

    private var visibleSegments: [BooksSection] {
        BooksSection.allCases.filter { permissionStore.can($0.requiredPermission) }
    }

    private var hasFinances: Bool { permissionStore.can("finances.view") }
    private var hasPipelineView: Bool { permissionStore.can("pipeline.view") }
    private var expensesScopeIsOwn: Bool {
        // If user has expenses.view but not at "all" scope, treat as own.
        permissionStore.can("expenses.view") && !permissionStore.hasFullAccess("expenses.view")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppHeader(headerType: .books)
                    .padding(.bottom, 8)

                if headerCollapsed {
                    underlineSegmentedControl
                        .background(OPSStyle.Colors.background)
                        .transition(.opacity)
                }

                ScrollView {
                    VStack(spacing: 0) {
                        // Dashboard — only when user has SOMETHING to put in it
                        if hasFinances || hasPipelineView {
                            MoneyDashboardHeader(viewModel: dashboardVM, onStatTap: { stat in
                                switch stat {
                                case .overdue:
                                    showARDetail = true
                                case .activeLeads, .staleLeads, .nextFollowUp:
                                    // Jump to Pipeline segment so the user can see the leads.
                                    selectedSegmentRaw = BooksSection.pipeline.rawValue
                                default:
                                    break
                                }
                            })
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
            // Default segment fallback: if persisted segment is no longer permitted, jump to first visible.
            if !visibleSegments.contains(selectedSegment), let first = visibleSegments.first {
                selectedSegmentRaw = first.rawValue
            }
        }
        // Bug 8ed0d2ed — let MainTabView (or any caller) request a specific
        // BOOKS segment via NotificationCenter. Used by expense / invoice
        // notification rail deep links to land the user directly on the
        // right tab content after the books tab is selected.
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
            case .pipeline:
                PipelineSectionView()
                    .environmentObject(dataController)
                    .environmentObject(permissionStore)
            case .estimates:
                EstimatesListView(embedded: true)
            case .invoices:
                InvoicesListView(embedded: true)
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
