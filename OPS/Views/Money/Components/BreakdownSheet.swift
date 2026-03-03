//
//  BreakdownSheet.swift
//  OPS
//
//  Itemized breakdown of payments, expenses, and outstanding invoices.
//  Shown when tapping the FinancialHealthBar.
//

import SwiftUI

struct BreakdownSheet: View {
    let payments: [MoneyDashboardViewModel.BreakdownItem]
    let expenses: [MoneyDashboardViewModel.BreakdownItem]
    let outstanding: [MoneyDashboardViewModel.BreakdownItem]
    var onItemTap: ((MoneyDashboardViewModel.BreakdownItem) -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                    if !payments.isEmpty {
                        breakdownSection(title: "PAYMENTS", items: payments, color: OPSStyle.Colors.accountingProfit)
                    }

                    if !expenses.isEmpty {
                        breakdownSection(title: "EXPENSES", items: expenses, color: OPSStyle.Colors.accountingCost)
                    }

                    if !outstanding.isEmpty {
                        breakdownSection(title: "OUTSTANDING", items: outstanding, color: OPSStyle.Colors.accountingReceivables)
                    }
                }
                .padding(OPSStyle.Layout.spacing3)
            }
            .background(OPSStyle.Colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("BREAKDOWN")
                        .font(OPSStyle.Typography.sectionLabel)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private func breakdownSection(title: String, items: [MoneyDashboardViewModel.BreakdownItem], color: Color) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(spacing: 1) {
                ForEach(items) { item in
                    Button {
                        onItemTap?(item)
                    } label: {
                        HStack {
                            Text(item.label)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .lineLimit(1)
                            Spacer()
                            Text(formatCurrency(item.amount))
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(color)
                        }
                        .padding(.vertical, OPSStyle.Layout.spacing2_5)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .fill(OPSStyle.Colors.cardBackgroundDark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}
