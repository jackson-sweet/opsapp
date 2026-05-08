//
//  MoneyDashboardHeader.swift
//  OPS
//
//  Combines PeriodToggle, FinancialHealthBar, and SmartStatCarousel
//  into the Money tab dashboard header. Also manages BreakdownSheet presentation.
//

import SwiftUI

struct MoneyDashboardHeader: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    @State private var showBreakdown = false
    var onStatTap: ((SmartStatCarousel.StatType) -> Void)?

    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            // Period toggle
            PeriodToggle(selectedPeriod: $viewModel.selectedPeriod)
                .padding(.horizontal, OPSStyle.Layout.spacing3)

            // Hero financial health bar
            FinancialHealthBar(
                totalSales: viewModel.totalSales,
                totalPayments: viewModel.totalPayments,
                totalExpenses: viewModel.totalExpenses,
                netCash: viewModel.netCash,
                onTap: { showBreakdown = true }
            )
            .padding(.horizontal, OPSStyle.Layout.spacing3)

            // Smart stat carousel — applies its own horizontal padding internally
            SmartStatCarousel(
                overdueCount: viewModel.overdueInvoicesCount,
                overdueValue: viewModel.overdueInvoicesValue,
                pendingEstimatesCount: viewModel.pendingEstimatesCount,
                pendingEstimatesValue: viewModel.pendingEstimatesValue,
                closeRate: viewModel.closeRate,
                avgDaysToPayment: viewModel.avgDaysToPayment,
                expensesTrend: viewModel.expensesTrend,
                topUnpaid: viewModel.topUnpaidInvoices,
                activeLeadCount: viewModel.activeLeadCount,
                weightedForecastValue: viewModel.weightedForecastValue,
                staleLeadsCount: viewModel.staleLeadsCount,
                nextFollowUpDue: viewModel.nextFollowUpDue,
                onStatTap: onStatTap
            )
        }
        .padding(.vertical, OPSStyle.Layout.spacing3)
        .sheet(isPresented: $showBreakdown) {
            BreakdownSheet(
                payments: viewModel.paymentBreakdown,
                expenses: viewModel.expenseBreakdown,
                outstanding: viewModel.outstandingInvoiceBreakdown
            )
            .presentationDetents([.large])
        }
    }
}
