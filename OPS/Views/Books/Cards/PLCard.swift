//
//  PLCard.swift
//  OPS
//
//  Books Phase 3 (Mission Deck) — Card 1 of the hero carousel.
//  P&L narrative: net cash hero + margin meter + IN/OUT row + two drill tiles.
//  "Am I making money this period?"
//
//  Spec: docs/superpowers/specs/2026-05-19-books-tab-mission-deck-rebuild.md § 5.1
//

import SwiftUI

struct PLCard: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    var onTapOutstanding: () -> Void
    var onTapForecast: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Derived

    /// Raw margin percent in -∞..100 range, used for the caption + color keying.
    /// Signed so the caption can read "-12% MARGIN" in rose on a loss month.
    private var marginPctSigned: Int {
        guard viewModel.totalPayments > 0 else { return 0 }
        return Int((viewModel.netCash / viewModel.totalPayments * 100).rounded())
    }

    /// Meter fill fraction clamped 0…1. Negative margins render an empty meter
    /// (the caption + hero number carry the sign instead).
    private var meterFraction: Double {
        guard viewModel.totalPayments > 0 else { return 0 }
        return max(0, min(1, viewModel.netCash / viewModel.totalPayments))
    }

    private var marginColor: Color {
        if marginPctSigned > 0 { return OPSStyle.Colors.olive }
        if marginPctSigned < 0 { return OPSStyle.Colors.rose }
        return OPSStyle.Colors.tertiaryText
    }

    private var isEmpty: Bool {
        viewModel.totalPayments == 0 && viewModel.totalExpenses == 0
    }

    private var isSkeleton: Bool {
        !viewModel.hasEverLoaded && viewModel.isLoading
    }

    // MARK: - Body

    var body: some View {
        if isSkeleton {
            skeletonView.padding(.horizontal, OPSStyle.Layout.spacing3_5)
        } else if viewModel.cardError(.pl) {
            BooksCardError(onRetry: { Task { await viewModel.retry(.pl) } })
        } else if isEmpty {
            emptyView.padding(.horizontal, OPSStyle.Layout.spacing3_5)
        } else {
            normalBody.padding(.horizontal, OPSStyle.Layout.spacing3_5)
        }
    }

    // MARK: - Normal body

    private var normalBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroBlock
            marginMeter.padding(.top, OPSStyle.Layout.spacing2)
            inOutRow.padding(.top, 10)
            HStack(spacing: OPSStyle.Layout.spacing2) {
                BooksDrillTile(
                    label: "OUTSTANDING",
                    value: currencyString(viewModel.overdueInvoicesValue),
                    sub: itemsLabel(viewModel.overdueInvoicesCount),
                    valueColor: OPSStyle.Colors.rose,
                    onTap: onTapOutstanding
                )
                BooksDrillTile(
                    label: "FORECAST",
                    value: currencyString(viewModel.pendingEstimatesValue),
                    sub: itemsLabel(viewModel.pendingEstimatesCount),
                    valueColor: OPSStyle.Colors.primaryAccent,
                    onTap: onTapForecast
                )
            }
            .padding(.top, OPSStyle.Layout.spacing4)
        }
    }

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NET CASH")
                .font(.custom("JetBrainsMono-Medium", size: 10))
                .tracking(2.0)  // 0.20em at 10pt
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text(viewModel.netCash, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(OPSStyle.Typography.heroNumber)
                .tracking(-1.5)  // ~-0.025em at 60pt
                .foregroundColor(viewModel.netCash >= 0 ? OPSStyle.Colors.primaryText : OPSStyle.Colors.rose)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())

            Text("\(marginPctSigned)% MARGIN")
                .font(.custom("JetBrainsMono-Medium", size: 11))
                .tracking(0.44)  // 0.04em at 11pt
                .foregroundColor(marginColor)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }

    private var marginMeter: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                    .fill(OPSStyle.Colors.warningStatus.opacity(0.30))  // tan-soft track per § 5.1
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                    .fill(OPSStyle.Colors.olive)
                    .frame(width: geo.size.width * meterFraction, height: 6)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)  // value is carried by margin caption
    }

    private var inOutRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PAYMENTS IN")
                    .font(.custom("JetBrainsMono-Medium", size: 9.5))
                    .tracking(1.71)  // 0.18em at 9.5pt
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text("+\(currencyString(viewModel.totalPayments))")
                    .font(.custom("JetBrainsMono-Medium", size: 14))
                    .foregroundColor(OPSStyle.Colors.oliveMobile)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("EXPENSES OUT")
                    .font(.custom("JetBrainsMono-Medium", size: 9.5))
                    .tracking(1.71)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text("\u{2212}\(currencyString(viewModel.totalExpenses))")  // U+2212 minus sign
                    .font(.custom("JetBrainsMono-Medium", size: 14))
                    .foregroundColor(OPSStyle.Colors.tanMobile)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("NET CASH")
                    .font(.custom("JetBrainsMono-Medium", size: 10))
                    .tracking(2.0)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text("$0")
                    .font(OPSStyle.Typography.heroNumber)
                    .tracking(-1.5)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .monospacedDigit()
                Text("// NO ACTIVITY THIS PERIOD")
                    .font(.custom("JetBrainsMono-Medium", size: 11))
                    .tracking(1.76)  // 0.16em at 11pt
                    .foregroundColor(OPSStyle.Colors.inactiveText)
            }
            HStack(spacing: OPSStyle.Layout.spacing2) {
                BooksDrillTile(
                    label: "OUTSTANDING",
                    value: "$0",
                    sub: "0 ITEMS",
                    valueColor: OPSStyle.Colors.tertiaryText
                )
                BooksDrillTile(
                    label: "FORECAST",
                    value: "$0",
                    sub: "0 ITEMS",
                    valueColor: OPSStyle.Colors.tertiaryText
                )
            }
            .padding(.top, OPSStyle.Layout.spacing4)
        }
    }

    // MARK: - Skeleton

    private var skeletonView: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                BooksSkeleton.bar(width: 80, height: 10)
                BooksSkeleton.bar(width: 220, height: 60)
                BooksSkeleton.bar(width: 100, height: 11)
            }
            BooksSkeleton.bar(width: nil, height: 6).padding(.top, OPSStyle.Layout.spacing2)
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    BooksSkeleton.bar(width: 80, height: 9)
                    BooksSkeleton.bar(width: 110, height: 14)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    BooksSkeleton.bar(width: 80, height: 9)
                    BooksSkeleton.bar(width: 110, height: 14)
                }
            }
            .padding(.top, 10)
            HStack(spacing: OPSStyle.Layout.spacing2) {
                BooksSkeleton.tile()
                BooksSkeleton.tile()
            }
            .padding(.top, OPSStyle.Layout.spacing4)
        }
    }

    // MARK: - Format helpers

    private func currencyString(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    private func itemsLabel(_ count: Int) -> String {
        "\(count) \(count == 1 ? "ITEM" : "ITEMS")"
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
