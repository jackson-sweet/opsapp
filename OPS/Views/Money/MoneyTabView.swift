//
//  MoneyTabView.swift
//  OPS
//
//  Container for the Money tab — segmented nav between Estimates, Invoices, Expenses.
//  Includes a collapsible MoneyDashboardHeader that scrolls away, with the
//  segmented control pinning below the AppHeader.
//

import SwiftUI

enum MoneySection: String, CaseIterable {
    case estimates = "ESTIMATES"
    case invoices  = "INVOICES"
    case expenses  = "EXPENSES"
}

// MARK: - Scroll Tracking Preference Key

private struct HeaderBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - MoneyTabView

struct MoneyTabView: View {
    @StateObject private var dashboardVM = MoneyDashboardViewModel()
    @StateObject private var estimateVM = EstimateViewModel()
    @StateObject private var invoiceVM = InvoiceViewModel()
    @StateObject private var expenseVM = ExpenseViewModel()

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext

    @State private var selectedSection: MoneySection = .estimates
    @State private var headerCollapsed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Fixed app header
                AppHeader(headerType: .pipeline)

                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(OPSStyle.Colors.cardBorder)

                // Pinned segmented control when header is collapsed
                if headerCollapsed {
                    underlineSegmentedControl
                        .background(OPSStyle.Colors.background)
                        .transition(.opacity)
                }

                // Scrollable content
                ScrollView {
                    VStack(spacing: 0) {
                        // Collapsible dashboard header
                        MoneyDashboardHeader(viewModel: dashboardVM)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: HeaderBottomKey.self,
                                        value: geo.frame(in: .named("scroll")).maxY
                                    )
                                }
                            )

                        // Inline segmented control (scrolls with content when not collapsed)
                        if !headerCollapsed {
                            underlineSegmentedControl
                        }

                        // List content for selected section
                        contentForSection
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
        }
        .onAppear {
            setupViewModels()
        }
    }

    // MARK: - Underline Segmented Control

    private var underlineSegmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(MoneySection.allCases, id: \.self) { section in
                Button {
                    withAnimation(OPSStyle.Animation.fast) {
                        selectedSection = section
                    }
                } label: {
                    VStack(spacing: OPSStyle.Layout.spacing2) {
                        Text(section.rawValue)
                            .font(OPSStyle.Typography.sectionLabel)
                            .foregroundColor(
                                selectedSection == section
                                    ? OPSStyle.Colors.primaryText
                                    : OPSStyle.Colors.secondaryText
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.top, OPSStyle.Layout.spacing2_5)

                        Rectangle()
                            .frame(height: OPSStyle.Layout.Border.thick)
                            .foregroundColor(
                                selectedSection == section
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

    // MARK: - Content Switching

    @ViewBuilder
    private var contentForSection: some View {
        Group {
            switch selectedSection {
            case .estimates:
                EstimatesListView(embedded: true)
            case .invoices:
                InvoicesListView(embedded: true)
            case .expenses:
                ExpensesListView(embedded: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(OPSStyle.Animation.fast, value: selectedSection)
    }

    // MARK: - Setup

    private func setupViewModels() {
        guard let companyId = dataController.currentUser?.companyId,
              !companyId.isEmpty else { return }
        dashboardVM.setup(companyId: companyId, modelContext: modelContext)
        estimateVM.setup(companyId: companyId)
        invoiceVM.setup(companyId: companyId)
        expenseVM.setup(companyId: companyId)
    }
}
