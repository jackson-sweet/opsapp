//
//  ForecastCard.swift
//  OPS
//
//  Books Phase 3 (Mission Deck) — Card 4 of the hero carousel.
//  Weighted pipeline value broken down by active stage, with per-stage
//  probability indicator. "What's coming if pipeline plays out?"
//
//  Spec: docs/superpowers/specs/2026-05-19-books-tab-mission-deck-rebuild.md § 5.4
//

import SwiftUI

struct ForecastCard: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    var onTapCloseRate: () -> Void
    var onTapStale: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Derived

    private var maxStageValue: Double {
        max(viewModel.weightedForecastByStage.map { $0.value }.max() ?? 0, 1)
    }

    private var isEmpty: Bool {
        viewModel.weightedForecastByStage.isEmpty
    }

    private var isSkeleton: Bool {
        !viewModel.hasEverLoaded && viewModel.isLoading
    }

    /// Composed VoiceOver summary for the whole card (spec § 8.1, Card 4).
    private var accessibilityCardLabel: String {
        "Forecast. \(viewModel.weightedForecastValue.formatted(.currency(code: "USD").precision(.fractionLength(0)))) weighted across \(viewModel.activeLeadCount) active opportunities. \(Int(viewModel.closeRate.rounded()))% close rate."
    }

    // MARK: - Body

    var body: some View {
        if isSkeleton {
            skeletonView.padding(.horizontal, OPSStyle.Layout.spacing3_5)
        } else if viewModel.cardError(.forecast) {
            BooksCardError(onRetry: { Task { await viewModel.retry(.forecast) } })
        } else if isEmpty {
            emptyView.padding(.horizontal, OPSStyle.Layout.spacing3_5)
        } else {
            normalBody.padding(.horizontal, OPSStyle.Layout.spacing3_5)
        }
    }

    // MARK: - Normal body

    private var normalBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Non-tile content folded into one VoiceOver element (the § 8.1
            // card summary). The drill tiles below stay individually navigable.
            VStack(alignment: .leading, spacing: 0) {
                heroBlock
                stageBars.padding(.top, OPSStyle.Layout.spacing4)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityCardLabel)

            HStack(spacing: OPSStyle.Layout.spacing2) {
                BooksDrillTile(
                    label: "CLOSE RATE",
                    value: "\(Int(viewModel.closeRate.rounded()))%",
                    sub: "LAST 90D",
                    valueColor: OPSStyle.Colors.olive,
                    onTap: onTapCloseRate,
                    accessibilityHint: "Double-tap for pipeline detail",
                    accessibilityLabelOverride: "Close rate, \(Int(viewModel.closeRate.rounded()))%, last 90 days"
                )
                BooksDrillTile(
                    label: "STALE",
                    value: "\(viewModel.staleLeadsCount)",
                    sub: "> 14D IDLE",
                    valueColor: OPSStyle.Colors.warningStatus,
                    onTap: onTapStale,
                    accessibilityHint: "Double-tap to view stale opps",
                    accessibilityLabelOverride: "Stale opportunities, \(viewModel.staleLeadsCount), over 14 days idle"
                )
            }
            .padding(.top, 22)
        }
    }

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WEIGHTED FORECAST")
                .font(.custom("JetBrainsMono-Medium", size: 10))
                .tracking(2.0)
                .foregroundColor(OPSStyle.Colors.primaryAccent)

            Text(viewModel.weightedForecastValue, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(OPSStyle.Typography.heroNumber)
                .tracking(-1.5)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)  // § 8.4 — hero number clamp
                .contentTransition(.numericText())

            Text("\(viewModel.activeLeadCount) ACTIVE OPPORTUNITIES")
                .font(.custom("JetBrainsMono-Medium", size: 11))
                .tracking(1.32)  // 0.12em at 11pt
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .monospacedDigit()
        }
    }

    // MARK: - Stage bars

    private var stageBars: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(viewModel.weightedForecastByStage) { row in
                stageRow(row)
            }
        }
    }

    private func stageRow(_ row: MoneyDashboardViewModel.StageForecast) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(row.stage.displayName)
                    .font(.custom("JetBrainsMono-Medium", size: 10))
                    .tracking(1.6)  // 0.16em at 10pt
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .textCase(.uppercase)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("×\(Int(row.avgProbability.rounded()))%")
                    .font(.custom("JetBrainsMono-Regular", size: 9))
                    .tracking(0.9)  // 0.10em at 9pt
                    .foregroundColor(OPSStyle.Colors.inactiveText)
                    .monospacedDigit()
                Text(row.value, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(.custom("JetBrainsMono-Medium", size: 13))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                        .fill(OPSStyle.Colors.primaryAccent.opacity(0.15))
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                        .fill(OPSStyle.Colors.primaryAccent)
                        .frame(width: geo.size.width * CGFloat(row.value / maxStageValue), height: 5)
                }
            }
            .frame(height: 5)
        }
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("WEIGHTED FORECAST")
                    .font(.custom("JetBrainsMono-Medium", size: 10))
                    .tracking(2.0)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text("$0")
                    .font(OPSStyle.Typography.heroNumber)
                    .tracking(-1.5)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .monospacedDigit()
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)  // § 8.4 — hero number clamp
                Text("// NO ACTIVE OPPORTUNITIES")
                    .font(.custom("JetBrainsMono-Medium", size: 11))
                    .tracking(1.76)
                    .foregroundColor(OPSStyle.Colors.inactiveText)
            }
            HStack(spacing: OPSStyle.Layout.spacing2) {
                BooksDrillTile(label: "CLOSE RATE", value: "—",  sub: "LAST 90D",   valueColor: OPSStyle.Colors.tertiaryText)
                BooksDrillTile(label: "STALE",      value: "0",  sub: "> 14D IDLE", valueColor: OPSStyle.Colors.tertiaryText)
            }
            .padding(.top, 22)
        }
    }

    // MARK: - Skeleton

    private var skeletonView: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                BooksSkeleton.bar(width: 160, height: 10)
                BooksSkeleton.bar(width: 240, height: 60)
                BooksSkeleton.bar(width: 160, height: 11)
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            BooksSkeleton.bar(width: 100, height: 10)
                            Spacer()
                            BooksSkeleton.bar(width: 36, height: 9)
                            BooksSkeleton.bar(width: 60, height: 13)
                        }
                        BooksSkeleton.bar(width: nil, height: 5)
                    }
                }
            }
            .padding(.top, OPSStyle.Layout.spacing4)
            HStack(spacing: OPSStyle.Layout.spacing2) {
                BooksSkeleton.tile()
                BooksSkeleton.tile()
            }
            .padding(.top, 22)
        }
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
