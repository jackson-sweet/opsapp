//
//  PLCard.swift
//  OPS
//
//  Books Phase 2 — Card 1 of the hero carousel.
//  P&L narrative: PAYMENTS IN − EXPENSES OUT = NET, margin bar, two drill tiles.
//  "Am I making money this period?"
//

import SwiftUI

struct PLCard: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    var onTapOutstanding: () -> Void
    var onTapForecast: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var marginFraction: Double {
        viewModel.totalPayments > 0
            ? max(0, viewModel.netCash / viewModel.totalPayments)
            : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            row(label: "PAYMENTS IN", value: viewModel.totalPayments, color: OPSStyle.Colors.successStatus, sign: "+")
            row(label: "EXPENSES OUT", value: viewModel.totalExpenses, color: OPSStyle.Colors.warningStatus, sign: "−")

            Divider().background(OPSStyle.Colors.cardBorder)

            HStack(alignment: .lastTextBaseline) {
                Text("NET CASH")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer()
                Text(viewModel.netCash, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(viewModel.netCash >= 0 ? OPSStyle.Colors.primaryText : OPSStyle.Colors.errorStatus)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            marginBar

            HStack(spacing: OPSStyle.Layout.spacing2) {
                tile(label: "OUTSTANDING", value: viewModel.overdueInvoicesValue, count: viewModel.overdueInvoicesCount, valueColor: OPSStyle.Colors.errorStatus, action: onTapOutstanding)
                tile(label: "FORECAST", value: viewModel.pendingEstimatesValue, count: viewModel.pendingEstimatesCount, valueColor: OPSStyle.Colors.primaryAccent, action: onTapForecast)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .onAppear {
            withAnimation(reduceMotion ? .none : OPSStyle.Animation.standard) {
                appeared = true
            }
        }
    }

    private func row(label: String, value: Double, color: Color, sign: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(color)
            Spacer()
            Text("\(sign)\(currencyString(value))")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(color)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }

    private var marginBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(OPSStyle.Colors.warningStatus.opacity(0.3))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(OPSStyle.Colors.successStatus)
                        .frame(width: appeared ? geo.size.width * marginFraction : 0, height: 4)
                        .animation(reduceMotion ? .none : OPSStyle.Animation.standard, value: appeared)
                }
            }
            .frame(height: 4)
            Text("\(Int((marginFraction * 100).rounded()))% MARGIN")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }

    private func tile(label: String, value: Double, count: Int, valueColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(OPSStyle.Typography.smallCaption).foregroundColor(OPSStyle.Colors.secondaryText)
                Text(currencyString(value)).font(OPSStyle.Typography.bodyBold).foregroundColor(valueColor).monospacedDigit()
                Text("\(count) \(count == 1 ? "ITEM" : "ITEMS")").font(OPSStyle.Typography.smallCaption).foregroundColor(OPSStyle.Colors.tertiaryText)
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
        .buttonStyle(PlainButtonStyle())
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
    }

    private func currencyString(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}

#if DEBUG
#Preview("PLCard — seeded") {
    PLCard(viewModel: .previewStub(), onTapOutstanding: {}, onTapForecast: {})
        .padding(.vertical, 24)
        .background(OPSStyle.Colors.background)
        .preferredColorScheme(.dark)
}

#Preview("PLCard — empty") {
    PLCard(viewModel: .previewEmpty(), onTapOutstanding: {}, onTapForecast: {})
        .padding(.vertical, 24)
        .background(OPSStyle.Colors.background)
        .preferredColorScheme(.dark)
}
#endif
