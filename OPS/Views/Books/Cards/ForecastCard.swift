//
//  ForecastCard.swift
//  OPS
//
//  Books Phase 2 — Card 4 of the hero carousel.
//  Weighted pipeline value broken down by active stage.
//  "What's coming if pipeline plays out?"
//

import SwiftUI

struct ForecastCard: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    var onTapCloseRate: () -> Void
    var onTapStale: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var maxStageValue: Double {
        max(viewModel.weightedForecastByStage.map { $0.value }.max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(viewModel.weightedForecastValue, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .monospacedDigit()
                .contentTransition(.numericText())

            Text("\(viewModel.activeLeadCount) ACTIVE OPPS")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("BY STAGE")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.top, OPSStyle.Layout.spacing2)

            if viewModel.weightedForecastByStage.isEmpty {
                Text("—")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.spacing3)
            } else {
                ForEach(Array(viewModel.weightedForecastByStage.enumerated()), id: \.offset) { idx, row in
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Text(row.stage.displayName)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(width: 88, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(OPSStyle.Colors.primaryAccent)
                                .frame(width: appeared ? geo.size.width * (row.value / maxStageValue) : 0, height: 10)
                                .animation(reduceMotion ? .none : OPSStyle.Animation.standard.delay(0.06 * Double(idx)), value: appeared)
                        }
                        .frame(height: 10)
                        Text(row.value, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .monospacedDigit()
                    }
                }
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                Button(action: onTapCloseRate) {
                    tileContent(label: "CLOSE RATE", value: "\(Int(viewModel.closeRate))%", color: OPSStyle.Colors.successStatus)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: onTapStale) {
                    tileContent(label: "STALE", value: "\(viewModel.staleLeadsCount)", color: OPSStyle.Colors.warningStatus)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
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
}

#if DEBUG
#Preview("ForecastCard — seeded") {
    ForecastCard(viewModel: .previewStub(), onTapCloseRate: {}, onTapStale: {})
        .padding(.vertical, 24)
        .background(OPSStyle.Colors.background)
        .preferredColorScheme(.dark)
}

#Preview("ForecastCard — empty") {
    ForecastCard(viewModel: .previewEmpty(), onTapCloseRate: {}, onTapStale: {})
        .padding(.vertical, 24)
        .background(OPSStyle.Colors.background)
        .preferredColorScheme(.dark)
}
#endif
