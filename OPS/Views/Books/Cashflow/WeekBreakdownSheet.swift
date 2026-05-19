//
//  WeekBreakdownSheet.swift
//  OPS
//
//  Bottom sheet listing every contributor to a tapped week, grouped into
//  inflows and outflows. Rows are stable: layer label + source label + amount.
//

import SwiftUI

struct WeekBreakdownSheet: View {
    let week: WeeklyProjection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3_5) {
                    section(
                        title: "+ INFLOWS · \(formatCurrency(week.inflows))",
                        rows: inflowRows
                    )
                    section(
                        title: "− OUTFLOWS · \(formatCurrency(week.outflows))",
                        rows: outflowRows
                    )
                    netRow
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, OPSStyle.Layout.spacing2_5)
                .padding(.bottom, OPSStyle.Layout.spacing4)
            }
        }
        .presentationDetents([.medium, .large])
        .background(OPSStyle.Colors.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("WEEK OF \(formatDate(week.weekStart))")
                .font(OPSStyle.Typography.microLabel)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Text("BALANCE \(formatCurrency(week.balance))")
                .font(OPSStyle.Typography.dataValueLg)
                .monospacedDigit()
                .foregroundColor(week.balance < 0 ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing3)
    }

    private var inflowRows: [ProjectionContributor] {
        week.contributors.filter { $0.amount > 0 }.sorted { $0.amount > $1.amount }
    }

    private var outflowRows: [ProjectionContributor] {
        week.contributors.filter { $0.amount < 0 }.sorted { $0.amount < $1.amount }
    }

    @ViewBuilder
    private func section(title: String, rows: [ProjectionContributor]) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(title)
                .font(OPSStyle.Typography.microLabel)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            if rows.isEmpty {
                Text("—")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            } else {
                ForEach(rows) { row in
                    contributorRow(row)
                    Divider().background(OPSStyle.Colors.cardBackgroundDark)
                }
            }
        }
    }

    private func contributorRow(_ row: ProjectionContributor) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.layer.displayName)
                    .font(OPSStyle.Typography.microLabel)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text(row.label)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            Spacer()
            Text(formatCurrency(row.amount))
                .font(OPSStyle.Typography.dataValue)
                .monospacedDigit()
                .foregroundColor(row.amount < 0 ? OPSStyle.Colors.rose : OPSStyle.Colors.primaryText)
        }
        .padding(.vertical, OPSStyle.Layout.spacing1 + 2)
    }

    private var netRow: some View {
        HStack {
            Text("= NET")
                .font(OPSStyle.Typography.microLabel)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
            Text(formatCurrency(week.net))
                .font(OPSStyle.Typography.dataValueLg)
                .monospacedDigit()
                .foregroundColor(week.net < 0 ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.primaryAccent)
        }
        .padding(.top, OPSStyle.Layout.spacing2)
    }

    private func formatCurrency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$0"
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: d).uppercased()
    }
}
