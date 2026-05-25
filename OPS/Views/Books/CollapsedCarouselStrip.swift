//
//  CollapsedCarouselStrip.swift
//  OPS
//
//  Books Phase 2 — one-line strip surfaced when the hero carousel collapses
//  on vertical scroll. Shows the active card's primary metric, an A/R glance,
//  and dot pagination so the user keeps situational awareness while reading
//  the list.
//

import SwiftUI

struct CollapsedCarouselStrip: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    var activeCard: HeroCarousel.CardID
    var visibleCards: [HeroCarousel.CardID]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var primaryLabel: String {
        switch activeCard {
        case .pl:        return "NET · \(viewModel.selectedPeriod.shortLabel)"
        case .cashFlow:  return "FLOW · \(viewModel.selectedPeriod.shortLabel)"
        case .ar:        return "A/R OPEN"
        case .forecast:  return "FORECAST"
        case .jobs:      return "JOBS NET"
        }
    }

    private var primaryValue: Double {
        switch activeCard {
        case .pl:        return viewModel.netCash
        case .cashFlow:  return viewModel.netCash
        case .ar:        return viewModel.outstandingInvoiceBreakdown.reduce(0) { $0 + $1.amount }
        case .forecast:  return viewModel.weightedForecastValue
        case .jobs:      return viewModel.topProjectsByNet.reduce(0) { $0 + $1.net }
        }
    }

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            VStack(alignment: .leading, spacing: 1) {
                Text(primaryLabel)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text(primaryValue, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .monospacedDigit()
                    .booksNumericContentTransition(reduceMotion: reduceMotion)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("A/R")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text(viewModel.overdueInvoicesValue, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                    .monospacedDigit()
            }
            HStack(spacing: 4) {
                ForEach(visibleCards) { card in
                    Capsule()
                        .fill(card == activeCard ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder)
                        .frame(width: card == activeCard ? 12 : 4, height: 4)
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.background.opacity(0.95))
        .overlay(
            Rectangle()
                .fill(OPSStyle.Colors.cardBorder)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
}

#if DEBUG
#Preview("CollapsedCarouselStrip — P&L active") {
    CollapsedCarouselStrip(
        viewModel: .previewStub(),
        activeCard: .pl,
        visibleCards: HeroCarousel.CardID.allCases
    )
    .background(OPSStyle.Colors.background)
    .preferredColorScheme(.dark)
}

#Preview("CollapsedCarouselStrip — A/R active") {
    CollapsedCarouselStrip(
        viewModel: .previewStub(),
        activeCard: .ar,
        visibleCards: HeroCarousel.CardID.allCases
    )
    .background(OPSStyle.Colors.background)
    .preferredColorScheme(.dark)
}
#endif
