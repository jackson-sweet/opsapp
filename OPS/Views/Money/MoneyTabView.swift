//
//  MoneyTabView.swift
//  OPS
//
//  Container for the Money tab — segmented nav between Estimates, Invoices, Expenses.
//  Replaces PipelineTabView as the primary financial management surface.
//

import SwiftUI

enum MoneySection: String, CaseIterable {
    case estimates = "ESTIMATES"
    case invoices  = "INVOICES"
    case expenses  = "EXPENSES"
}

struct MoneyTabView: View {
    @StateObject private var estimateVM = EstimateViewModel()
    @StateObject private var invoiceVM = InvoiceViewModel()
    @StateObject private var expenseVM = ExpenseViewModel()

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject var appState: AppState

    @State private var selectedSection: MoneySection = .estimates
    @State private var headerCollapsed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppHeader(headerType: .pipeline)

                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(OPSStyle.Colors.cardBorder)

                SegmentedControl(selection: $selectedSection, options: [
                    (.estimates, "ESTIMATES"),
                    (.invoices, "INVOICES"),
                    (.expenses, "EXPENSES")
                ])
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2)

                // Content
                Group {
                    switch selectedSection {
                    case .estimates:
                        EstimatesListView()
                    case .invoices:
                        InvoicesListView()
                    case .expenses:
                        ExpensesListView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(OPSStyle.Animation.fast, value: selectedSection)
            }
            .background(OPSStyle.Colors.background.ignoresSafeArea())
        }
        .onAppear {
            setupViewModels()
        }
    }

    // MARK: - Setup

    private func setupViewModels() {
        guard let companyId = dataController.currentUser?.companyId,
              !companyId.isEmpty else { return }
        estimateVM.setup(companyId: companyId)
        invoiceVM.setup(companyId: companyId)
        expenseVM.setup(companyId: companyId)
    }
}
