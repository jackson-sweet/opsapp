//
//  FinancialHealthBar.swift
//  OPS
//
//  Hero financial visualization — sales container with stacked payments/expenses bars.
//  Tapping opens the breakdown sheet.
//

import SwiftUI

struct FinancialHealthBar: View {
    let totalSales: Double
    let totalPayments: Double
    let totalExpenses: Double
    let netCash: Double
    let onTap: () -> Void

    @State private var animatedPaymentsFraction: CGFloat = 0
    @State private var animatedExpensesFraction: CGFloat = 0

    private var paymentsFraction: CGFloat {
        totalSales > 0 ? CGFloat(totalPayments / totalSales) : 0
    }

    private var expensesFraction: CGFloat {
        totalSales > 0 ? CGFloat(totalExpenses / totalSales) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            // Sales label
            HStack(alignment: .firstTextBaseline) {
                Text("SALES")
                    .font(OPSStyle.Typography.sectionLabel)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
                Text(formatCurrency(totalSales))
                    .font(OPSStyle.Typography.headingLarge)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }

            // Bar container
            Button(action: onTap) {
                VStack(spacing: 2) {
                    // Payments row
                    barRow(
                        label: "Payments",
                        amount: totalPayments,
                        fraction: animatedPaymentsFraction,
                        color: OPSStyle.Colors.accountingProfit
                    )

                    // Expenses row
                    barRow(
                        label: "Expenses",
                        amount: totalExpenses,
                        fraction: animatedExpensesFraction,
                        color: OPSStyle.Colors.accountingCost
                    )
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .fill(OPSStyle.Colors.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
            }
            .buttonStyle(.plain)

            // Net cash
            HStack {
                Spacer()
                Text("Net Cash: \(netCash >= 0 ? "+" : "")\(formatCurrency(netCash))")
                    .font(OPSStyle.Typography.heading)
                    .foregroundColor(netCash >= 0 ? OPSStyle.Colors.accountingProfit : OPSStyle.Colors.accountingOverdue)
                Spacer()
            }
        }
        .onAppear {
            animateBars()
        }
        .onChange(of: totalSales) { _, _ in
            animateBars()
        }
    }

    @ViewBuilder
    private func barRow(label: String, amount: Double, fraction: CGFloat, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Empty background
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(Color.clear)

                // Filled portion
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(color)
                    .frame(width: max(0, geo.size.width * min(fraction, 1.0)))

                // Label on bar
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Text(label)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(.white)
                    Text(formatCurrency(amount))
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal, OPSStyle.Layout.spacing2)
            }
        }
        .frame(height: 28)
    }

    private func animateBars() {
        let reducedMotion = UIAccessibility.isReduceMotionEnabled
        if reducedMotion {
            animatedPaymentsFraction = paymentsFraction
            animatedExpensesFraction = expensesFraction
        } else {
            animatedPaymentsFraction = 0
            animatedExpensesFraction = 0
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                animatedPaymentsFraction = paymentsFraction
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
                animatedExpensesFraction = expensesFraction
            }
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let absValue = abs(value)
        if absValue >= 1000 {
            return String(format: "$%.1fK", absValue / 1000)
        }
        return String(format: "$%.0f", absValue)
    }
}
