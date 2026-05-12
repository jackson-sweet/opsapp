//
//  JobsCard.swift
//  OPS
//
//  Books Phase 2 — Card 5 of the hero carousel.
//  Diverging profit/loss bars for top jobs in the period.
//  "Which jobs made me money? Which lost it?"
//

import SwiftUI

struct JobsCard: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    var onTapProfitable: () -> Void
    var onTapLosers: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var maxAbsNet: Double {
        max(viewModel.topProjectsByNet.map { abs($0.net) }.max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("JOBS · NET BY PROJECT · \(viewModel.selectedPeriod.pillLabel)")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            if viewModel.topProjectsByNet.isEmpty {
                Text("—")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.spacing3)
            } else {
                ForEach(Array(viewModel.topProjectsByNet.enumerated()), id: \.element.id) { idx, row in
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Text(row.title.uppercased())
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(width: 88, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(row.net >= 0 ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)
                                .frame(width: appeared ? geo.size.width * (abs(row.net) / maxAbsNet) : 0, height: 8)
                                .animation(reduceMotion ? .none : OPSStyle.Animation.standard.delay(0.06 * Double(idx)), value: appeared)
                        }
                        .frame(height: 8)
                        Text((row.net >= 0 ? "+" : "") + currencyString(row.net))
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(row.net >= 0 ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)
                            .monospacedDigit()
                    }
                }
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                Button(action: onTapProfitable) {
                    tileContent(label: "PROFITABLE", value: "\(viewModel.profitableProjectCount)", color: OPSStyle.Colors.successStatus)
                }
                .buttonStyle(PlainButtonStyle())

                tileContent(label: "AVG MARGIN", value: "\(Int((viewModel.avgProjectMargin * 100).rounded()))%", color: OPSStyle.Colors.primaryText)

                Button(action: onTapLosers) {
                    tileContent(label: "LOSERS", value: "\(viewModel.losersProjectCount)", color: OPSStyle.Colors.errorStatus)
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
        .onAppear {
            withAnimation(reduceMotion ? .none : OPSStyle.Animation.standard) { appeared = true }
        }
    }

    private func tileContent(label: String, value: String, color: Color) -> some View {
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

    private func currencyString(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}
