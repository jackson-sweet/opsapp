//
//  CashFlowCard.swift
//  OPS
//
//  Books Phase 2 — Card 2 of the hero carousel.
//  Paired in/out bars by ISO week. "What's my cash rhythm?"
//

import SwiftUI
import Charts

struct CashFlowCard: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    var onTapDays: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct WeekRow: Identifiable {
        let id = UUID()
        let weekStart: Date
        let inAmount: Double
        let outAmount: Double
    }

    private var weeks: [WeekRow] {
        let inDict = Dictionary(uniqueKeysWithValues: viewModel.paymentsByWeek.map { ($0.weekStart, $0.amount) })
        let outDict = Dictionary(uniqueKeysWithValues: viewModel.expensesByWeek.map { ($0.weekStart, $0.amount) })
        let allWeeks = Set(inDict.keys).union(outDict.keys).sorted()
        return allWeeks.map { ws in
            WeekRow(weekStart: ws, inAmount: inDict[ws] ?? 0, outAmount: outDict[ws] ?? 0)
        }
    }

    private var avgPerWeek: Double {
        let nonZero = weeks.filter { $0.inAmount > 0 }
        guard !nonZero.isEmpty else { return 0 }
        return nonZero.map { $0.inAmount }.reduce(0, +) / Double(nonZero.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CASH FLOW · \(viewModel.selectedPeriod.pillLabel)")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Text(viewModel.netCash, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Spacer()
                legend
            }

            if weeks.isEmpty {
                emptyState
            } else {
                Chart(weeks) { row in
                    BarMark(
                        x: .value("Week", row.weekStart, unit: .weekOfYear),
                        y: .value("In", row.inAmount),
                        width: .ratio(0.4)
                    )
                    .foregroundStyle(OPSStyle.Colors.successStatus)
                    .position(by: .value("Direction", "In"))

                    BarMark(
                        x: .value("Week", row.weekStart, unit: .weekOfYear),
                        y: .value("Out", row.outAmount),
                        width: .ratio(0.4)
                    )
                    .foregroundStyle(OPSStyle.Colors.warningStatus)
                    .position(by: .value("Direction", "Out"))
                }
                .frame(height: 120)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                        AxisValueLabel(format: .dateTime.week(.weekOfMonth))
                            .foregroundStyle(OPSStyle.Colors.tertiaryText)
                    }
                }
                .chartYAxis(.hidden)
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                tileContent(label: "SALES", value: currencyString(viewModel.totalSales))
                tileContent(label: "AVG/WK", value: currencyString(avgPerWeek), color: OPSStyle.Colors.successStatus)
                Button(action: onTapDays) {
                    tileContent(label: "DAYS", value: String(format: "%.1f", viewModel.avgDaysToPayment))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
    }

    private var legend: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            legendDot(color: OPSStyle.Colors.successStatus, label: "IN")
            legendDot(color: OPSStyle.Colors.warningStatus, label: "OUT")
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(OPSStyle.Typography.smallCaption).foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }

    private func tileContent(label: String, value: String, color: Color = OPSStyle.Colors.primaryText) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(OPSStyle.Typography.smallCaption).foregroundColor(OPSStyle.Colors.secondaryText)
            Text(value).font(OPSStyle.Typography.bodyBold).foregroundColor(color).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .cornerRadius(OPSStyle.Layout.smallCornerRadius)
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            Text("—")
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
        }
        .frame(height: 120)
    }

    private func currencyString(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}
